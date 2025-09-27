# Interactive Network Testing Tool
# Supports TCP, UDP port testing and ping tests

function Show-Menu {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "    Interactive Network Testing Tool by CP   " -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. TCP Port Test" -ForegroundColor Green
    Write-Host "2. UDP Port Test" -ForegroundColor Green
    Write-Host "3. Ping Test" -ForegroundColor Green
    Write-Host "4. Multiple Port Scan (TCP)" -ForegroundColor Green
    Write-Host "5. Common Ports Test" -ForegroundColor Green
    Write-Host "6. Exit" -ForegroundColor Red
    Write-Host ""
}

function Test-TCPPort {
    param(
        [string]$ComputerName,
        [int]$Port,
        [int]$Timeout = 5000
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $tcpClient.BeginConnect($ComputerName, $Port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne($Timeout, $false)
        
        if ($wait) {
            try {
                $tcpClient.EndConnect($connect)
                $result = $true
            }
            catch {
                $result = $false
            }
        }
        else {
            $result = $false
        }
        
        $tcpClient.Close()
        return $result
    }
    catch {
        return $false
    }
}

function Test-UDPPort {
    param(
        [string]$ComputerName,
        [int]$Port,
        [int]$Timeout = 5000
    )
    
    try {
        $udpClient = New-Object System.Net.Sockets.UdpClient
        $udpClient.Client.ReceiveTimeout = $Timeout
        
        # Connect to the remote host
        $udpClient.Connect($ComputerName, $Port)
        
        # Send a test packet
        $testData = [System.Text.Encoding]::ASCII.GetBytes("test")
        $udpClient.Send($testData, $testData.Length) | Out-Null
        
        # Try to receive data (this will timeout if port is closed/filtered)
        $remoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        
        try {
            $udpClient.Receive([ref]$remoteEndpoint)
            $result = $true
        }
        catch [System.Net.Sockets.SocketException] {
            # ICMP Port Unreachable means the port is closed but host is reachable
            if ($_.Exception.SocketErrorCode -eq [System.Net.Sockets.SocketError]::ConnectionReset) {
                $result = $false
            }
            else {
                # Timeout or other error - port might be open but not responding
                $result = "Unknown"
            }
        }
        
        $udpClient.Close()
        return $result
    }
    catch {
        return $false
    }
}

function Test-PingHost {
    param(
        [string]$ComputerName,
        [int]$Count = 4,
        [int]$Timeout = 5000
    )
    
    Write-Host "Pinging $ComputerName with $Count packets..." -ForegroundColor Yellow
    
    $successCount = 0
    $totalTime = 0
    $minTime = [int]::MaxValue
    $maxTime = 0
    
    for ($i = 1; $i -le $Count; $i++) {
        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $result = $ping.Send($ComputerName, $Timeout)
            
            if ($result.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                $time = $result.RoundtripTime
                Write-Host "Reply from $($result.Address): time=$($time)ms TTL=$($result.Options.Ttl)" -ForegroundColor Green
                $successCount++
                $totalTime += $time
                if ($time -lt $minTime) { $minTime = $time }
                if ($time -gt $maxTime) { $maxTime = $time }
            }
            else {
                Write-Host "Request timed out or failed: $($result.Status)" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "Ping failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        if ($i -lt $Count) { Start-Sleep -Milliseconds 1000 }
    }
    
    Write-Host ""
    Write-Host "Ping statistics for $ComputerName :" -ForegroundColor Cyan
    Write-Host "    Packets: Sent = $Count, Received = $successCount, Lost = $($Count - $successCount) ($(($Count - $successCount) * 100 / $Count)% loss)" -ForegroundColor Cyan
    
    if ($successCount -gt 0) {
        $avgTime = $totalTime / $successCount
        Write-Host "Approximate round trip times in milli-seconds:" -ForegroundColor Cyan
        Write-Host "    Minimum = $($minTime)ms, Maximum = $($maxTime)ms, Average = $($avgTime.ToString('F0'))ms" -ForegroundColor Cyan
    }
}

function Get-UserInput {
    param(
        [string]$Prompt,
        [string]$Default = ""
    )
    
    if ($Default) {
        $input = Read-Host "$Prompt (default: $Default)"
        if ([string]::IsNullOrWhiteSpace($input)) {
            return $Default
        }
    }
    else {
        $input = Read-Host $Prompt
    }
    
    return $input
}

function Test-SingleTCPPort {
    Write-Host "=== TCP Port Test ===" -ForegroundColor Cyan
    $hostname = Get-UserInput "Enter hostname or IP address"
    $port = Get-UserInput "Enter port number"
    $timeout = Get-UserInput "Enter timeout in milliseconds" "5000"
    
    if ([string]::IsNullOrWhiteSpace($hostname) -or [string]::IsNullOrWhiteSpace($port)) {
        Write-Host "Hostname and port are required!" -ForegroundColor Red
        return
    }
    
    if (-not [int]::TryParse($port, [ref]$port)) {
        Write-Host "Invalid port number!" -ForegroundColor Red
        return
    }
    
    if (-not [int]::TryParse($timeout, [ref]$timeout)) {
        $timeout = 5000
    }
    
    Write-Host "Testing TCP connection to $hostname`:$port..." -ForegroundColor Yellow
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $result = Test-TCPPort -ComputerName $hostname -Port $port -Timeout $timeout
    $stopwatch.Stop()
    
    if ($result) {
        Write-Host "SUCCESS: TCP port $port is OPEN on $hostname (Response time: $($stopwatch.ElapsedMilliseconds)ms)" -ForegroundColor Green
    }
    else {
        Write-Host "FAILED: TCP port $port is CLOSED or FILTERED on $hostname" -ForegroundColor Red
    }
}

function Test-SingleUDPPort {
    Write-Host "=== UDP Port Test ===" -ForegroundColor Cyan
    Write-Host "Note: UDP testing is less reliable than TCP. Results may show 'Unknown' for filtered ports." -ForegroundColor Yellow
    
    $hostname = Get-UserInput "Enter hostname or IP address"
    $port = Get-UserInput "Enter port number"
    $timeout = Get-UserInput "Enter timeout in milliseconds" "5000"
    
    if ([string]::IsNullOrWhiteSpace($hostname) -or [string]::IsNullOrWhiteSpace($port)) {
        Write-Host "Hostname and port are required!" -ForegroundColor Red
        return
    }
    
    if (-not [int]::TryParse($port, [ref]$port)) {
        Write-Host "Invalid port number!" -ForegroundColor Red
        return
    }
    
    if (-not [int]::TryParse($timeout, [ref]$timeout)) {
        $timeout = 5000
    }
    
    Write-Host "Testing UDP connection to $hostname`:$port..." -ForegroundColor Yellow
    
    $result = Test-UDPPort -ComputerName $hostname -Port $port -Timeout $timeout
    
    switch ($result) {
        $true { Write-Host "SUCCESS: UDP port $port appears to be OPEN on $hostname" -ForegroundColor Green }
        $false { Write-Host "FAILED: UDP port $port is CLOSED on $hostname" -ForegroundColor Red }
        "Unknown" { Write-Host "UNKNOWN: UDP port $port status is uncertain on $hostname (may be open but not responding)" -ForegroundColor Yellow }
    }
}

function Test-MultipleTCPPorts {
    Write-Host "=== Multiple TCP Port Scan ===" -ForegroundColor Cyan
    $hostname = Get-UserInput "Enter hostname or IP address"
    $portRange = Get-UserInput "Enter port range (e.g., '80,443,8080' or '1-100')"
    
    if ([string]::IsNullOrWhiteSpace($hostname) -or [string]::IsNullOrWhiteSpace($portRange)) {
        Write-Host "Hostname and port range are required!" -ForegroundColor Red
        return
    }
    
    $ports = @()
    
    if ($portRange -like "*-*") {
        # Range format (e.g., 1-100)
        $rangeParts = $portRange -split "-"
        if ($rangeParts.Count -eq 2) {
            $startPort = [int]$rangeParts[0]
            $endPort = [int]$rangeParts[1]
            $ports = $startPort..$endPort
        }
    }
    else {
        # Comma-separated format (e.g., 80,443,8080)
        $ports = $portRange -split "," | ForEach-Object { [int]$_.Trim() }
    }
    
    if ($ports.Count -eq 0) {
        Write-Host "Invalid port range format!" -ForegroundColor Red
        return
    }
    
    Write-Host "Scanning $($ports.Count) ports on $hostname..." -ForegroundColor Yellow
    
    $openPorts = @()
    $closedPorts = @()
    
    foreach ($port in $ports) {
        Write-Progress -Activity "Scanning ports" -Status "Testing port $port" -PercentComplete (($ports.IndexOf($port) / $ports.Count) * 100)
        
        $result = Test-TCPPort -ComputerName $hostname -Port $port -Timeout 3000
        
        if ($result) {
            $openPorts += $port
            Write-Host "Port $port`: OPEN" -ForegroundColor Green
        }
        else {
            $closedPorts += $port
        }
    }
    
    Write-Progress -Completed -Activity "Scanning ports"
    
    Write-Host ""
    Write-Host "=== Scan Results ===" -ForegroundColor Cyan
    Write-Host "Open ports ($($openPorts.Count)): $($openPorts -join ', ')" -ForegroundColor Green
    Write-Host "Closed/Filtered ports: $($closedPorts.Count)" -ForegroundColor Red
}

function Test-CommonPorts {
    Write-Host "=== Common Ports Test ===" -ForegroundColor Cyan
    $hostname = Get-UserInput "Enter hostname or IP address"
    
    if ([string]::IsNullOrWhiteSpace($hostname)) {
        Write-Host "Hostname is required!" -ForegroundColor Red
        return
    }
    
    $commonPorts = @{
        21 = "FTP"
        22 = "SSH"
        23 = "Telnet"
        25 = "SMTP"
        53 = "DNS"
        80 = "HTTP"
        110 = "POP3"
        135 = "RPC"
        139 = "NetBIOS"
        143 = "IMAP"
        443 = "HTTPS"
        445 = "SMB"
        993 = "IMAPS"
        995 = "POP3S"
        1433 = "SQL Server"
        3389 = "RDP"
        5985 = "WinRM HTTP"
        5986 = "WinRM HTTPS"
        8080 = "HTTP Alt"
    }
    
    Write-Host "Testing common ports on $hostname..." -ForegroundColor Yellow
    
    $results = @()
    
    foreach ($port in $commonPorts.Keys) {
        Write-Progress -Activity "Testing common ports" -Status "Testing $($commonPorts[$port]) (port $port)" -PercentComplete (($results.Count / $commonPorts.Count) * 100)
        
        $result = Test-TCPPort -ComputerName $hostname -Port $port -Timeout 3000
        
        $status = if ($result) { "OPEN" } else { "CLOSED" }
        $color = if ($result) { "Green" } else { "Red" }
        
        $results += [PSCustomObject]@{
            Port = $port
            Service = $commonPorts[$port]
            Status = $status
        }
        
        Write-Host "Port $port ($($commonPorts[$port])): $status" -ForegroundColor $color
    }
    
    Write-Progress -Completed -Activity "Testing common ports"
    
    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    $openPorts = $results | Where-Object { $_.Status -eq "OPEN" }
    Write-Host "Open services found: $($openPorts.Count)" -ForegroundColor Green
    
    if ($openPorts.Count -gt 0) {
        $openPorts | ForEach-Object {
            Write-Host "  $($_.Port) - $($_.Service)" -ForegroundColor Green
        }
    }
}

function Test-PingWrapper {
    Write-Host "=== Ping Test ===" -ForegroundColor Cyan
    $hostname = Get-UserInput "Enter hostname or IP address"
    $count = Get-UserInput "Enter number of packets to send" "4"
    $timeout = Get-UserInput "Enter timeout in milliseconds" "5000"
    
    if ([string]::IsNullOrWhiteSpace($hostname)) {
        Write-Host "Hostname is required!" -ForegroundColor Red
        return
    }
    
    if (-not [int]::TryParse($count, [ref]$count)) {
        $count = 4
    }
    
    if (-not [int]::TryParse($timeout, [ref]$timeout)) {
        $timeout = 5000
    }
    
    Test-PingHost -ComputerName $hostname -Count $count -Timeout $timeout
}

# Main script loop
do {
    Show-Menu
    $choice = Read-Host "Please select an option (1-6)"
    
    switch ($choice) {
        "1" { 
            Test-SingleTCPPort
            Write-Host ""
            Read-Host "Press Enter to continue"
        }
        "2" { 
            Test-SingleUDPPort
            Write-Host ""
            Read-Host "Press Enter to continue"
        }
        "3" { 
            Test-PingWrapper
            Write-Host ""
            Read-Host "Press Enter to continue"
        }
        "4" { 
            Test-MultipleTCPPorts
            Write-Host ""
            Read-Host "Press Enter to continue"
        }
        "5" { 
            Test-CommonPorts
            Write-Host ""
            Read-Host "Press Enter to continue"
        }
        "6" { 
            Write-Host "Goodbye!" -ForegroundColor Green
            break
        }
        default { 
            Write-Host "Invalid option. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while ($choice -ne "6")