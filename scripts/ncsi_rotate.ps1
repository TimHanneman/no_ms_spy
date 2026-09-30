# ==========================================================================
#  ncsi_rotate.ps1
#  Installed by no_ms_spy.bat in the scripts folder of its Program Files
#  folder. Runs as SYSTEM every few hours and at startup.
#
#  Moves the Windows connectivity check (NCSI) between several providers so
#  no single provider sees every check. Each run:
#    1. Turns itself off and puts the original settings back when
#       restore.signal exists or no_ms_spy.cfg says CONNECTIVITY_CHECK=0.
#       Does nothing when the config does not mention the setting.
#    2. Checks whether Windows is rejecting the provider in use now. A
#       suspected provider stays in place and is removed only after three
#       runs in a row where Windows reports no internet while it answers.
#    3. Picks a random name for the DNS check, confirms it resolves to its
#       expected address, and points the DNS check at it. Skipped when a
#       fixed NCSI_DNS_HOST is set in no_ms_spy.cfg.
#    4. Picks a random provider, checks its reply matches the expected
#       pattern, is the same on two requests and is under 1 KB, then points
#       the connectivity check at it.
#
#  Files, relative to the install folder:
#    config\no_ms_spy.cfg     selections and earlier values
#    config\ncsi_state.txt    failure counts and rejected providers
#    config\restore.signal    written by no_ms_spy.bat to turn the rotation off
#    logs\ncsi_rotate.log     log
# ==========================================================================

$ErrorActionPreference = 'Stop'

# This script is in the scripts folder; config and logs are next to it.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$installDir = Split-Path -Parent $scriptDir
$configDir = Join-Path $installDir 'config'
$logDir = Join-Path $installDir 'logs'
$configFile = Join-Path $configDir 'no_ms_spy.cfg'
$stateFile = Join-Path $configDir 'ncsi_state.txt'
$logFile = Join-Path $logDir 'ncsi_rotate.log'
$signalFile = Join-Path $configDir 'restore.signal'
$ncsiKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet'
$taskPath = '\no_ms_spy\'
$taskNames = @('NCSI rotate', 'NCSI rotate at startup')
$maxReplyBytes = 1024
$failuresBeforeNotice = 3
$rejectionsBeforeRemoval = 3
$maxLogBytes = 1MB
$keepLogLines = 2000

# Web check providers. The reply must match the pattern, a regular
# expression. The user agent is the one each provider receives most, so the
# check blends in with that traffic. {firefox} is replaced with the current
# Firefox version number.
function New-WebProvider($url, $pattern, $userAgent) {
    return [pscustomobject]@{
        Url       = $url
        Host      = ([Uri]$url).Host
        Pattern   = $pattern
        UserAgent = $userAgent
    }
}

$webPool = @(
    New-WebProvider 'http://www.msftconnecttest.com/connecttest.txt' '^Microsoft Connect Test$' 'Microsoft NCSI'
    New-WebProvider 'http://detectportal.firefox.com/success.txt' '^success\s*$' 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:{firefox}.0) Gecko/20100101 Firefox/{firefox}.0'
    New-WebProvider 'http://captive.apple.com/hotspot-detect.html' '<TITLE>Success</TITLE>' 'CaptiveNetworkSupport-481.100.1 wispr'
    New-WebProvider 'http://nmcheck.gnome.org/check_network_status.txt' '^NetworkManager is online\s*$' 'NetworkManager/1.48.0'
    New-WebProvider 'http://ping.archlinux.org/nm-check.txt' '^NetworkManager is online\s*$' 'NetworkManager/1.48.0'
    New-WebProvider 'http://fedoraproject.org/static/hotspot.txt' '^OK\s*$' 'NetworkManager/1.48.0'
)

# DNS check names. Each must resolve to exactly one IPv4 address that does
# not change; the IPv6 address is used for the IPv6 DNS check. The root
# server names are used because a recursive resolver already knows their
# addresses from its startup, so it can answer without asking anyone, and
# when it does ask, the root servers already see all of its traffic.
# Addresses are written in standard short form so they compare exactly.
function New-DnsName($name, $ipv4, $ipv6) {
    return [pscustomobject]@{ Name = $name; IPv4 = $ipv4; IPv6 = $ipv6 }
}

$dnsPool = @(
    New-DnsName 'dns.msftncsi.com'   '131.107.255.255' 'fd3e:4f5a:5b81::1'
    New-DnsName 'a.root-servers.net' '198.41.0.4'      '2001:503:ba3e::2:30'
    New-DnsName 'b.root-servers.net' '170.247.170.2'   '2801:1b8:10::b'
    New-DnsName 'c.root-servers.net' '192.33.4.12'     '2001:500:2::c'
    New-DnsName 'd.root-servers.net' '199.7.91.13'     '2001:500:2d::d'
    New-DnsName 'e.root-servers.net' '192.203.230.10'  '2001:500:a8::e'
    New-DnsName 'f.root-servers.net' '192.5.5.241'     '2001:500:2f::f'
    New-DnsName 'g.root-servers.net' '192.112.36.4'    '2001:500:12::d0d'
    New-DnsName 'h.root-servers.net' '198.97.190.53'   '2001:500:1::53'
    New-DnsName 'i.root-servers.net' '192.36.148.17'   '2001:7fe::53'
    New-DnsName 'j.root-servers.net' '192.58.128.30'   '2001:503:c27::2:30'
    New-DnsName 'k.root-servers.net' '193.0.14.129'    '2001:7fd::1'
    New-DnsName 'l.root-servers.net' '199.7.83.42'     '2001:500:9f::42'
    New-DnsName 'm.root-servers.net' '202.12.27.33'    '2001:dc3::35'
)


function Write-Log($level, $message) {
    # The logs folder is created on first use.
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }
    # Past the size limit, only the newest lines are kept, in the same file.
    if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt $maxLogBytes) {
        $newest = Get-Content -Path $logFile -Tail $keepLogLines
        Set-Content -Path $logFile -Value $newest
    }
    $line = '{0} {1} {2}' -f (Get-Date -Format 's'), $level, $message
    Add-Content -Path $logFile -Value $line
}


function Send-Notification($message) {
    # Log file, Windows event log (Application, source no_ms_spy) and a
    # message box on every signed-in session where msg.exe exists.
    Write-Log 'ERROR' $message
    try {
        & "$env:SystemRoot\System32\eventcreate.exe" /T ERROR /ID 101 /L APPLICATION /SO no_ms_spy /D $message | Out-Null
    }
    catch {
    }
    $msgExe = "$env:SystemRoot\System32\msg.exe"
    if (Test-Path $msgExe) {
        try {
            & $msgExe '*' '/TIME:60' "no_ms_spy: $message" | Out-Null
        }
        catch {
        }
    }
}


function Get-FirefoxVersion {
    # Firefox ships a new version every four weeks, and version 128 shipped
    # on 9 July 2024, so the current version is estimated from the date. A
    # fixed, aging version number would stand out among real Firefox
    # requests. Schedule shifts can put the estimate one version off, which
    # still matches users who have not updated yet.
    $days = ((Get-Date) - [datetime]'2024-07-09').TotalDays
    return 128 + [int][math]::Floor($days / 28)
}


function Resolve-UserAgent($template) {
    return $template.Replace('{firefox}', [string](Get-FirefoxVersion))
}


function ConvertTo-Count($text) {
    # A damaged number counts as 0 instead of stopping every later run.
    $number = 0
    if ([int]::TryParse($text, [ref]$number) -and $number -ge 0) {
        return $number
    }
    return 0
}


function Read-State {
    # One line per provider or DNS name:
    #   name|failures in a row|times Windows seemed to reject it
    $state = @{}
    if (Test-Path $stateFile) {
        foreach ($line in Get-Content $stateFile) {
            $parts = $line -split '\|'
            if ($parts.Count -eq 3 -and $parts[0] -ne '') {
                $state[$parts[0]] = [pscustomobject]@{
                    Failures   = ConvertTo-Count $parts[1]
                    Rejections = ConvertTo-Count $parts[2]
                }
            }
        }
    }
    return $state
}


function Get-HostState($state, $probeHost) {
    if (-not $state.ContainsKey($probeHost)) {
        $state[$probeHost] = [pscustomobject]@{ Failures = 0; Rejections = 0 }
    }
    return $state[$probeHost]
}


function Save-State($state) {
    $lines = foreach ($probeHost in $state.Keys) {
        $entry = $state[$probeHost]
        '{0}|{1}|{2}' -f $probeHost, $entry.Failures, $entry.Rejections
    }
    Set-Content -Path $stateFile -Value $lines
}


function Get-ProbeText($url, $userAgent) {
    # Returns the reply text, or $null for a redirect, a status other than
    # 200 or a reply over $maxReplyBytes. Only reads that many bytes.
    $request = [System.Net.HttpWebRequest]::Create($url)
    $request.UserAgent = $userAgent
    $request.AllowAutoRedirect = $false
    $request.Timeout = 10000
    $request.ReadWriteTimeout = 10000

    $response = $request.GetResponse()
    try {
        if ([int]$response.StatusCode -ne 200) {
            return $null
        }

        $stream = $response.GetResponseStream()
        $buffer = New-Object byte[] ($maxReplyBytes + 1)
        $total = 0
        while ($total -lt $buffer.Length) {
            $read = $stream.Read($buffer, $total, $buffer.Length - $total)
            if ($read -le 0) {
                break
            }
            $total += $read
        }

        if ($total -gt $maxReplyBytes) {
            return $null
        }
        return [System.Text.Encoding]::UTF8.GetString($buffer, 0, $total)
    }
    finally {
        $response.Close()
    }
}


function New-Result($ok, $reason, $text) {
    return [pscustomobject]@{ Ok = $ok; Reason = $reason; Text = $text }
}


function Test-Probe($entry) {
    $userAgent = Resolve-UserAgent $entry.UserAgent
    try {
        $first = Get-ProbeText $entry.Url $userAgent
        if ($null -eq $first) {
            return New-Result $false 'redirect, HTTP status other than 200, or reply over 1 KB' ''
        }
        if ($first -notmatch $entry.Pattern) {
            return New-Result $false 'reply did not match the expected pattern - captive portal or changed page' ''
        }

        # Windows compares the reply with a stored copy, so a reply that
        # changes between requests (timestamp, hash) cannot be used.
        Start-Sleep -Seconds 2
        $second = Get-ProbeText $entry.Url $userAgent
        if ($second -cne $first) {
            return New-Result $false 'reply changes between requests, so Windows cannot compare it' ''
        }
        return New-Result $true '' $first
    }
    catch {
        $reason = $_.Exception.Message
        if ($reason -match '\(40[03]\)') {
            $reason = "$reason - the provider may not accept this user agent"
        }
        return New-Result $false $reason ''
    }
}


function Test-HasIPv6($probeHost) {
    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($probeHost)
        $ipv6 = @($addresses | Where-Object { $_.AddressFamily -eq 'InterNetworkV6' })
        return $ipv6.Count -gt 0
    }
    catch {
        return $false
    }
}


function Test-DnsEntry($entry) {
    # Ok when the name resolves to exactly its expected IPv4 address.
    # IPv6Ok when it also resolves to exactly its expected IPv6 address.
    try {
        $addresses = @([System.Net.Dns]::GetHostAddresses($entry.Name))
    }
    catch {
        return [pscustomobject]@{ Ok = $false; IPv6Ok = $false; Reason = "lookup failed: $($_.Exception.Message)" }
    }

    $ipv4 = @($addresses | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.ToString() })
    if ($ipv4.Count -ne 1 -or $ipv4[0] -ne $entry.IPv4) {
        $found = $ipv4 -join ', '
        return [pscustomobject]@{ Ok = $false; IPv6Ok = $false; Reason = "resolved to [$found] instead of $($entry.IPv4) - address changed or DNS is redirected" }
    }

    $ipv6Ok = $false
    if ($entry.IPv6) {
        $ipv6 = @($addresses | Where-Object { $_.AddressFamily -eq 'InterNetworkV6' } | ForEach-Object { $_.ToString() })
        $ipv6Ok = ($ipv6.Count -eq 1 -and $ipv6[0] -eq $entry.IPv6)
    }
    return [pscustomobject]@{ Ok = $true; IPv6Ok = $ipv6Ok; Reason = '' }
}


function Update-DnsProbe($state, $configLines, $windowsOnline) {
    # A fixed DNS check host set in no_ms_spy.cfg by the administrator wins.
    if (@($configLines | Where-Object { $_ -match '^NCSI_DNS_HOST=' }).Count -gt 0) {
        return
    }

    $pool = $dnsPool

    $currentName = (Get-ItemProperty -Path $ncsiKey).ActiveDnsProbeHost
    $candidates = @($pool | Where-Object { $_.Name -ne $currentName })
    if ($candidates.Count -eq 0) {
        $candidates = $pool
    }

    foreach ($entry in @($candidates | Get-Random -Count $candidates.Count)) {
        $nameState = Get-HostState $state "dns:$($entry.Name)"
        $result = Test-DnsEntry $entry

        if (-not $result.Ok) {
            # While Windows reports no internet, every name is expected to
            # fail, so failures are neither counted nor reported.
            if ($windowsOnline) {
                $nameState.Failures++
                Write-Log 'WARN' "DNS $($entry.Name): $($result.Reason)"
                if ($nameState.Failures -eq $failuresBeforeNotice) {
                    Send-Notification "DNS check name $($entry.Name) failed $failuresBeforeNotice times in a row: $($result.Reason)"
                }
            }
            continue
        }

        $nameState.Failures = 0
        Set-ItemProperty -Path $ncsiKey -Name ActiveDnsProbeHost -Value $entry.Name
        Set-ItemProperty -Path $ncsiKey -Name ActiveDnsProbeContent -Value $entry.IPv4
        Write-Log 'INFO' "DNS check now uses $($entry.Name)"

        # The IPv6 DNS check moves to this name when its IPv6 address
        # matches, otherwise to another name whose IPv6 address matches.
        $v6Entry = $null
        if ($result.IPv6Ok) {
            $v6Entry = $entry
        }
        else {
            $others = @($pool | Where-Object { $_.Name -ne $entry.Name -and $_.IPv6 })
            if ($others.Count -gt 0) {
                foreach ($other in @($others | Get-Random -Count $others.Count)) {
                    if ((Test-DnsEntry $other).IPv6Ok) {
                        $v6Entry = $other
                        break
                    }
                }
            }
        }

        if ($v6Entry) {
            Set-ItemProperty -Path $ncsiKey -Name ActiveDnsProbeHostV6 -Value $v6Entry.Name
            Set-ItemProperty -Path $ncsiKey -Name ActiveDnsProbeContentV6 -Value $v6Entry.IPv6
            Write-Log 'INFO' "IPv6 DNS check now uses $($v6Entry.Name)"
        }
        else {
            Write-Log 'WARN' 'No DNS check name resolved to its expected IPv6 address; the IPv6 DNS check was left unchanged'
        }
        (Get-HostState $state 'notice:dns').Failures = 0
        return
    }

    if ($windowsOnline) {
        # One notice after three runs in a row, not a message box every run.
        $notice = Get-HostState $state 'notice:dns'
        $notice.Failures++
        $message = 'None of the DNS check names resolved to their expected address. The current DNS check was kept.'
        if ($notice.Failures -eq $failuresBeforeNotice) {
            Send-Notification $message
        }
        else {
            Write-Log 'WARN' $message
        }
    }
    else {
        Write-Log 'INFO' 'No DNS check name resolved; the network appears to be offline'
    }
}


function Set-WindowsDefaultWebProbe {
    # Windows' own web check, which Windows always accepts.
    Set-ItemProperty -Path $ncsiKey -Name ActiveWebProbeHost -Value 'www.msftconnecttest.com'
    Set-ItemProperty -Path $ncsiKey -Name ActiveWebProbePath -Value 'connecttest.txt'
    Set-ItemProperty -Path $ncsiKey -Name ActiveWebProbeContent -Value 'Microsoft Connect Test'
    Set-ItemProperty -Path $ncsiKey -Name ActiveWebProbeHostV6 -Value 'ipv6.msftconnecttest.com'
    Set-ItemProperty -Path $ncsiKey -Name ActiveWebProbePathV6 -Value 'connecttest.txt'
    Set-ItemProperty -Path $ncsiKey -Name ActiveWebProbeContentV6 -Value 'Microsoft Connect Test'
}


function Restore-Original($configLines) {
    # Puts back the connectivity check values no_ms_spy.bat saved in the
    # config before the rotation first changed them, then removes the tasks.
    $pattern = '^ORIG=OV#SYS\\Services\\NlaSvc\\Parameters\\Internet;([^;]+);=CONNECTIVITY_CHECK;([^;]+);(.*)$'
    foreach ($line in $configLines) {
        if ($line -match $pattern) {
            $name = $Matches[1]
            $type = $Matches[2]
            $data = $Matches[3]
            if ($type -eq '-') {
                Remove-ItemProperty -Path $ncsiKey -Name $name -ErrorAction SilentlyContinue
            }
            else {
                Set-ItemProperty -Path $ncsiKey -Name $name -Value $data
            }
        }
    }

    foreach ($taskName in $taskNames) {
        Unregister-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    Remove-Item -Path $signalFile -ErrorAction SilentlyContinue
    # The state only matters while the rotation runs.
    Remove-Item -Path $stateFile -ErrorAction SilentlyContinue
    Write-Log 'INFO' 'Rotation turned off: original connectivity check restored and tasks removed'
}


try {
    # Only one copy runs at a time; the hourly and startup tasks can overlap.
    $lock = New-Object System.Threading.Mutex($false, 'Global\no_ms_spy_ncsi_rotate')
    try {
        $haveLock = $lock.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        # A previous run ended without releasing the lock; it is ours now.
        $haveLock = $true
    }
    if (-not $haveLock) {
        exit 0
    }

    $configLines = @()
    if (Test-Path $configFile) {
        $configLines = @(Get-Content $configFile)
    }

    # Turn off only on a clear instruction. A missing config or one without
    # the setting is left alone, so a config being rewritten at this moment
    # cannot switch the rotation off by mistake.
    if ((Test-Path $signalFile) -or ($configLines -contains 'CONNECTIVITY_CHECK=0')) {
        Restore-Original $configLines
        exit 0
    }
    if ($configLines -notcontains 'CONNECTIVITY_CHECK=1') {
        Write-Log 'WARN' 'CONNECTIVITY_CHECK is not set in no_ms_spy.cfg; nothing was changed this run'
        exit 0
    }

    $pool = $webPool
    $state = Read-State
    $currentHost = (Get-ItemProperty -Path $ncsiKey).ActiveWebProbeHost

    # If Windows reports no internet while the provider in use still
    # answers correctly, Windows may not accept that provider's reply. But
    # Windows' status can also lag after an outage or a wake from sleep. So
    # a suspected provider is kept in place and tested again on the next
    # runs, and only removed after $rejectionsBeforeRemoval runs in a row.
    # Any run where Windows reports internet, or where the provider does not
    # answer (a real outage), ends the streak.
    $profiles = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue)
    $onlineProfiles = @($profiles | Where-Object {
            $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet'
        })
    $windowsOnline = $onlineProfiles.Count -gt 0
    $currentEntry = $pool | Where-Object { $_.Host -eq $currentHost } | Select-Object -First 1

    $justRejected = $false
    $keepCurrent = $false
    if ($currentEntry) {
        $currentState = Get-HostState $state $currentHost
        if ($currentState.Rejections -lt $rejectionsBeforeRemoval) {
            if ($windowsOnline -or $profiles.Count -eq 0) {
                $currentState.Rejections = 0
            }
            else {
                $check = Test-Probe $currentEntry
                if (-not $check.Ok) {
                    $currentState.Rejections = 0
                }
                else {
                    $currentState.Rejections++
                    if ($currentState.Rejections -ge $rejectionsBeforeRemoval) {
                        $justRejected = $true
                        Send-Notification "Windows reported no internet on $rejectionsBeforeRemoval runs in a row while $currentHost answered correctly. It was removed from the rotation. Delete its line in config\ncsi_state.txt to try it again."

                        # A second rejected provider suggests a Windows update
                        # changed how the check works, so only the Windows default
                        # check is used from now on.
                        $rejected = @($pool | Where-Object { (Get-HostState $state $_.Host).Rejections -ge $rejectionsBeforeRemoval })
                        if ($rejected.Count -ge 2) {
                            foreach ($provider in $pool) {
                                if ($provider.Host -ne 'www.msftconnecttest.com') {
                                    (Get-HostState $state $provider.Host).Rejections = $rejectionsBeforeRemoval
                                }
                            }
                            Save-State $state
                            Set-WindowsDefaultWebProbe
                            Send-Notification 'Windows rejected two connectivity check providers, which suggests a Windows update changed how the check works. Only the Windows default check is used now. Delete config\ncsi_state.txt to try the providers again.'
                            exit 0
                        }
                    }
                    else {
                        $keepCurrent = $true
                        Write-Log 'WARN' "Windows reports no internet while $currentHost answers correctly ($($currentState.Rejections) of $rejectionsBeforeRemoval runs in a row); kept in place to test again"
                    }
                }
            }
        }
    }

    Update-DnsProbe $state $configLines $windowsOnline

    if ($keepCurrent) {
        Save-State $state
        exit 0
    }

    $usable = @($pool | Where-Object { (Get-HostState $state $_.Host).Rejections -lt $rejectionsBeforeRemoval })
    $candidates = @($usable | Where-Object { $_.Host -ne $currentHost })
    if ($candidates.Count -eq 0) {
        $candidates = $usable
    }
    if ($candidates.Count -eq 0) {
        # Leaving Windows on a provider it rejects would make it report no
        # internet from now on, so its own default check is put back.
        Save-State $state
        Set-WindowsDefaultWebProbe
        $message = 'Every connectivity check provider has been rejected by Windows, so the Windows default check was put back. Delete config\ncsi_state.txt to try the providers again.'
        if ($justRejected) {
            Send-Notification $message
        }
        else {
            Write-Log 'WARN' $message
        }
        exit 1
    }

    foreach ($entry in @($candidates | Get-Random -Count $candidates.Count)) {
        $hostState = Get-HostState $state $entry.Host
        $result = Test-Probe $entry

        if (-not $result.Ok) {
            # While Windows reports no internet, every provider is expected
            # to fail, so failures are neither counted nor reported.
            if ($windowsOnline) {
                $hostState.Failures++
                Write-Log 'WARN' "$($entry.Host): $($result.Reason)"
                if ($hostState.Failures -eq $failuresBeforeNotice) {
                    Send-Notification "$($entry.Host) failed $failuresBeforeNotice checks in a row: $($result.Reason)"
                }
            }
            continue
        }

        $hostState.Failures = 0
        $path = ([Uri]$entry.Url).PathAndQuery.TrimStart('/')
        Set-ItemProperty -Path $ncsiKey -Name ActiveWebProbeHost -Value $entry.Host
        Set-ItemProperty -Path $ncsiKey -Name ActiveWebProbePath -Value $path
        Set-ItemProperty -Path $ncsiKey -Name ActiveWebProbeContent -Value $result.Text

        # The IPv6 check needs a provider with an IPv6 address. If the
        # provider chosen above has none, another working provider with one
        # is used, so the IPv6 check does not stay with Microsoft.
        $v6Entry = $null
        $v6Text = ''
        if (Test-HasIPv6 $entry.Host) {
            $v6Entry = $entry
            $v6Text = $result.Text
        }
        else {
            $others = @($usable | Where-Object { $_.Host -ne $entry.Host })
            if ($others.Count -gt 0) {
                foreach ($other in @($others | Get-Random -Count $others.Count)) {
                    if (-not (Test-HasIPv6 $other.Host)) {
                        continue
                    }
                    $otherResult = Test-Probe $other
                    if ($otherResult.Ok) {
                        $v6Entry = $other
                        $v6Text = $otherResult.Text
                        break
                    }
                }
            }
        }

        if ($v6Entry) {
            $v6Path = ([Uri]$v6Entry.Url).PathAndQuery.TrimStart('/')
            Set-ItemProperty -Path $ncsiKey -Name ActiveWebProbeHostV6 -Value $v6Entry.Host
            Set-ItemProperty -Path $ncsiKey -Name ActiveWebProbePathV6 -Value $v6Path
            Set-ItemProperty -Path $ncsiKey -Name ActiveWebProbeContentV6 -Value $v6Text
            Write-Log 'INFO' "IPv6 connectivity check now uses $($v6Entry.Host)"
        }
        else {
            Write-Log 'WARN' 'No working provider has an IPv6 address; the IPv6 check was left unchanged'
        }

        (Get-HostState $state 'notice:none').Failures = 0
        Save-State $state
        Write-Log 'INFO' "Connectivity check now uses $($entry.Host)"
        Write-Output "  Using    $($entry.Host) for the connectivity check"
        exit 0
    }

    $message = 'None of the connectivity check providers answered correctly. The current setting was kept.'
    if ($windowsOnline) {
        # One notice after three runs in a row, not a message box every run.
        $notice = Get-HostState $state 'notice:none'
        $notice.Failures++
        if ($notice.Failures -eq $failuresBeforeNotice) {
            Send-Notification $message
        }
        else {
            Write-Log 'WARN' $message
        }
    }
    else {
        Write-Log 'INFO' 'No provider answered; the network appears to be offline'
    }
    Save-State $state
    exit 1
}
catch {
    $message = "Connectivity check rotation stopped with an error: $($_.Exception.Message)"
    try {
        # A lasting fault would otherwise show a message box on every run.
        $noticeFile = Join-Path $configDir 'rotation_error_notice.txt'
        $recent = (Test-Path $noticeFile) -and (((Get-Date) - (Get-Item $noticeFile).LastWriteTime).TotalHours -lt 24)
        if ($recent) {
            Write-Log 'ERROR' $message
        }
        else {
            Send-Notification $message
            Set-Content -Path $noticeFile -Value $message
        }
    }
    catch {
    }
    exit 1
}
