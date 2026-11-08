[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = 'Chat efímero'

$script:ChatPort = 5000
$script:DiscoveryPort = 5001
$script:MaxPeople = 20
$script:me = ''
$script:isHost = $false
$script:running = $false
$script:endMessage = $null
$script:typed = ''
$script:players = @()
$script:peers = New-Object System.Collections.ArrayList
$script:listener = $null
$script:beacon = $null
$script:beaconTargets = @()
$script:conn = $null
$script:hostPort = $script:ChatPort
$script:hostIp = ''
$script:roomName = ''
$script:lastBeacon = [DateTime]::MinValue

$Str = @{
    Title        = 'Chat efímero'
    AskName      = 'Tu nombre'
    DefaultName  = 'Shyguy'
    Hello        = 'Hola, {0}'
    MenuHost     = '  [1] Crear una sala'
    MenuJoin     = '  [2] Unirme a una sala'
    MenuQuit     = '  [Q] Salir'
    RoomPrompt   = 'Nombre de la sala [{0}]'
    Checking     = 'Revisando que el nombre esté libre...'
    PortError    = 'No se pudo abrir la sala en este PC. Revisa el firewall.'
    Searching    = 'Buscando salas en la red...'
    NoRooms      = 'No se encontró ninguna sala.'
    RoomsHeader  = 'Salas encontradas:'
    RoomLine     = '  [{0}] {1}  ·  {2}  ·  {3} conectados  ·  {4}'
    RoomsKeys    = 'Número o nombre = unirse · R = buscar de nuevo · M = escribir IP · Q = volver'
    Choose       = 'Elige'
    ManualPrompt = 'IP del host (o IP:puerto)'
    ManualBad    = 'Eso no parece una IP válida.'
    Connecting   = 'Conectando...'
    ConnectFail  = 'No se pudo conectar con esa sala.'
    NoReply      = 'La sala no respondió.'
    RoomFull     = 'La sala está llena.'
    Rejected     = 'La sala no te dejó entrar.'
    HeaderRoom   = 'Sala: {0}  ·  IP {1}'
    HeaderYou    = 'Eres: '
    HostHint     = 'Los demás te encuentran en "Unirme a una sala".'
    Hints        = '/lista = quién está · /q = salir'
    RoomCreated  = 'Sala creada.'
    Joined       = '{0} se unió'
    Left         = '{0} salió'
    You          = '(tú)'
    NameChanged  = 'Tu nombre en esta sala es {0}'
    WhoLine      = 'Conectados ({0}): {1}'
    CmdUnknown   = 'Comando desconocido. Prueba /lista o /q'
    RoomClosed   = 'La sala se cerró.'
    PressKey     = 'Presiona una tecla para continuar...'
}

function Clean-Name([string]$name, [int]$max) {
    $clean = ($name -replace '[^\p{L}\p{N}_\- ]', '').Trim()
    $clean = $clean -replace ' +', '_'
    if ($clean.Length -gt $max) { $clean = $clean.Substring(0, $max).Trim('_') }
    $clean
}

function Clean-Text([string]$text, [int]$max) {
    $clean = ($text -replace '\p{Cc}', '').Trim()
    if ($clean.Length -gt $max) { $clean = $clean.Substring(0, $max) }
    $clean
}

function New-RandomCode([int]$length) {
    $chars = 'abcdefghjkmnpqrstuvwxyz23456789'
    -join (1..$length | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

function Get-UniqueName([string]$name, $taken) {
    $candidate = $name
    $n = 2
    while (@($taken | Where-Object { $_ -ieq $candidate }).Count -gt 0) {
        $candidate = $name + $n
        $n++
    }
    $candidate
}

function Split-Fields([string]$line, [int]$count) {
    $parts = ([regex]'\|').Split($line, $count)
    , $parts
}

function Get-NameColor([string]$name) {
    $palette = 'Cyan', 'Magenta', 'Green', 'Yellow', 'Red', 'DarkCyan', 'DarkMagenta', 'White'
    $sum = 0
    foreach ($ch in $name.ToCharArray()) { $sum += [int]$ch }
    $palette[$sum % $palette.Count]
}

function Get-InputLimit {
    $width = 80
    try { $width = $Host.UI.RawUI.WindowSize.Width } catch { }
    [math]::Max(10, [math]::Min(300, $width - $script:me.Length - 4))
}

function Show-Input {
    Write-Host $script:me -NoNewline -ForegroundColor (Get-NameColor $script:me)
    Write-Host ('> ' + $script:typed) -NoNewline
}

function Clear-Input {
    Write-Host ("`r" + (' ' * ($script:me.Length + 2 + $script:typed.Length)) + "`r") -NoNewline
}

function Write-Chat([string]$who, [string]$text) {
    Clear-Input
    Write-Host $who -NoNewline -ForegroundColor (Get-NameColor $who)
    if ($who -ieq $script:me) { Write-Host (' ' + $Str.You) -NoNewline -ForegroundColor DarkGray }
    Write-Host (': ' + $text)
    Show-Input
}

function Write-System([string]$text) {
    Clear-Input
    Write-Host ('* ' + $text)
    Show-Input
}

function Show-Notice([string]$text) {
    Write-Host ''
    Write-Host $text
    Write-Host $Str.PressKey
    [void][Console]::ReadKey($true)
}

function New-Peer($client) {
    [pscustomobject]@{
        Client  = $client
        Stream  = $client.GetStream()
        Decoder = [System.Text.Encoding]::UTF8.GetDecoder()
        Buffer  = ''
        Name    = ''
        Joined  = $false
        Closed  = $false
        Seen    = Get-Date
    }
}

function Read-Lines($peer) {
    $lines = New-Object System.Collections.ArrayList
    try {
        $sock = $peer.Client.Client
        while ($peer.Stream.DataAvailable) {
            $bytes = New-Object byte[] 4096
            $n = $peer.Stream.Read($bytes, 0, 4096)
            if ($n -le 0) { break }
            $chars = New-Object char[] ($n + 4)
            $got = $peer.Decoder.GetChars($bytes, 0, $n, $chars, 0)
            if ($got -gt 0) { $peer.Buffer += [string]::new($chars, 0, $got) }
        }
        if ($sock.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead) -and $sock.Available -eq 0) {
            $peer.Closed = $true
        }
    } catch {
        $peer.Closed = $true
    }
    if ($peer.Buffer.Length -gt 65536) {
        $peer.Buffer = ''
        $peer.Closed = $true
    }
    while (($idx = $peer.Buffer.IndexOf("`n")) -ge 0) {
        $line = $peer.Buffer.Substring(0, $idx).TrimEnd("`r")
        $peer.Buffer = $peer.Buffer.Substring($idx + 1)
        if ($line.Length -gt 0) { [void]$lines.Add($line) }
    }
    $lines
}

function Send-Line($peer, [string]$text) {
    if ($peer.Closed) { return }
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text + "`n")
        $peer.Stream.Write($bytes, 0, $bytes.Length)
    } catch {
        $peer.Closed = $true
    }
}

function Send-All([string]$line) {
    foreach ($peer in @($script:peers)) {
        if ($peer.Joined -and -not $peer.Closed) { Send-Line $peer $line }
    }
}

function Get-PlayerNames {
    $names = @($script:me)
    foreach ($peer in $script:peers) {
        if ($peer.Joined -and -not $peer.Closed) { $names += $peer.Name }
    }
    , $names
}

function Send-Who {
    Send-All ('WHO|' + ((Get-PlayerNames) -join ','))
}

function Post-Chat([string]$who, [string]$text) {
    Write-Chat $who $text
    Send-All ('CHAT|' + $who + '|' + $text)
}

function Announce([string]$text) {
    Write-System $text
    Send-All ('SYS|' + $text)
}

function Remove-Peer($peer) {
    [void]$script:peers.Remove($peer)
    $peer.Closed = $true
    try { $peer.Client.Close() } catch { }
    if (-not $peer.Joined) { return }
    Announce ($Str.Left -f $peer.Name)
    Send-Who
}

function Handle-PeerLine($peer, [string]$line) {
    $kind = ($line -split '\|', 2)[0]
    if (-not $peer.Joined) {
        if ($kind -ne 'HI') { return }
        $joined = @($script:peers | Where-Object { $_.Joined -and -not $_.Closed }).Count
        if ($joined -ge ($script:MaxPeople - 1)) {
            Send-Line $peer 'NO|full'
            $peer.Closed = $true
            return
        }
        $fields = Split-Fields $line 2
        $name = Clean-Name ([string]$fields[1]) 12
        if ($name.Length -eq 0) { $name = $Str.DefaultName + (Get-Random -Minimum 10 -Maximum 99) }
        $name = Get-UniqueName $name (Get-PlayerNames)
        $peer.Name = $name
        $peer.Joined = $true
        Send-Line $peer ('WELCOME|' + $name + '|' + $script:roomName)
        Announce ($Str.Joined -f $name)
        Send-Who
        return
    }
    switch ($kind) {
        'MSG' {
            $fields = Split-Fields $line 2
            $text = Clean-Text ([string]$fields[1]) 300
            if ($text.Length -gt 0) { Post-Chat $peer.Name $text }
        }
        'BYE' { $peer.Closed = $true }
    }
}

function Handle-HostLine([string]$line) {
    $kind = ($line -split '\|', 2)[0]
    switch ($kind) {
        'CHAT' {
            $fields = Split-Fields $line 3
            Write-Chat ([string]$fields[1]) ([string]$fields[2])
        }
        'SYS' {
            $fields = Split-Fields $line 2
            Write-System ([string]$fields[1])
        }
        'WHO' {
            $fields = Split-Fields $line 2
            $script:players = @(([string]$fields[1]) -split ',' | Where-Object { $_ })
        }
        'CLOSE' { End-Chat $Str.RoomClosed }
    }
}

function End-Chat([string]$message) {
    if ($script:running) {
        $script:endMessage = $message
        $script:running = $false
    }
}

function Get-NetworkInfo {
    $targets = New-Object System.Collections.ArrayList
    $best = $null
    $fallback = $null
    foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($nic.OperationalStatus -ne 'Up') { continue }
        if ($nic.NetworkInterfaceType -eq 'Loopback') { continue }
        $props = $nic.GetIPProperties()
        foreach ($ua in $props.UnicastAddresses) {
            if ($ua.Address.AddressFamily -ne 'InterNetwork') { continue }
            $octets = $ua.Address.GetAddressBytes()
            if ($octets[0] -eq 169 -and $octets[1] -eq 254) { continue }
            $mask = $ua.IPv4Mask.GetAddressBytes()
            $bc = for ($i = 0; $i -lt 4; $i++) { $octets[$i] -bor (255 - $mask[$i]) }
            $bcText = $bc -join '.'
            if (-not $targets.Contains($bcText)) { [void]$targets.Add($bcText) }
            if (-not $fallback) { $fallback = $ua.Address.ToString() }
            if (-not $best -and $props.GatewayAddresses.Count -gt 0) { $best = $ua.Address.ToString() }
        }
    }
    [void]$targets.Add('255.255.255.255')
    $chosen = if ($best) { $best } else { $fallback }
    [pscustomobject]@{ Ip = $chosen; Targets = @($targets) }
}

function Send-Beacon {
    $names = Get-PlayerNames
    $payload = 'EPH1|' + $script:roomName + '|' + $script:me + '|' + $script:hostPort + '|' + @($names).Count
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    foreach ($target in $script:beaconTargets) {
        try { [void]$script:beacon.Send($bytes, $bytes.Length, $target, $script:DiscoveryPort) } catch { }
    }
}

function New-DiscoveryListener {
    $udp = [System.Net.Sockets.UdpClient]::new()
    $udp.ExclusiveAddressUse = $false
    $udp.Client.SetSocketOption('Socket', 'ReuseAddress', $true)
    $udp.Client.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, $script:DiscoveryPort))
    $udp
}

function Read-Beacons($udp, $rooms) {
    try {
        while ($udp.Available -gt 0) {
            $ep = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
            $data = $udp.Receive([ref]$ep)
            $fields = Split-Fields ([System.Text.Encoding]::UTF8.GetString($data)) 5
            if ($fields.Count -ge 5 -and $fields[0] -eq 'EPH1') {
                $key = $ep.Address.ToString() + ':' + $fields[3]
                $rooms[$key] = [pscustomobject]@{
                    Name  = $fields[1]
                    Owner = $fields[2]
                    Ip    = $ep.Address.ToString()
                    Port  = [int]$fields[3]
                    Count = [int]$fields[4]
                }
            }
        }
    } catch { }
}

function Find-Rooms([int]$ms) {
    $rooms = @{}
    $udp = $null
    try { $udp = New-DiscoveryListener } catch { }
    $end = (Get-Date).AddMilliseconds($ms)
    $frames = '|', '/', '-', '\'
    $i = 0
    while ((Get-Date) -lt $end) {
        if ($udp) { Read-Beacons $udp $rooms }
        Write-Host ("`r  " + $frames[$i % 4]) -NoNewline
        Start-Sleep -Milliseconds 120
        $i++
    }
    if ($udp) { $udp.Close() }
    Write-Host ("`r" + (' ' * 10) + "`r") -NoNewline
    $rooms.Values | Sort-Object Name
}

function Step-Host {
    $now = Get-Date
    while ($script:listener.Pending()) {
        try {
            $client = $script:listener.AcceptTcpClient()
            $client.NoDelay = $true
            [void]$script:peers.Add((New-Peer $client))
        } catch { }
    }
    foreach ($peer in @($script:peers)) {
        try {
            foreach ($line in (Read-Lines $peer)) {
                $peer.Seen = $now
                Handle-PeerLine $peer $line
            }
        } catch {
            $peer.Closed = $true
        }
        if ($peer.Closed) {
            Remove-Peer $peer
            continue
        }
        if (-not $peer.Joined -and ($now - $peer.Seen).TotalSeconds -gt 5) { Remove-Peer $peer }
    }
    if (($now - $script:lastBeacon).TotalSeconds -ge 2) {
        Send-Beacon
        $script:lastBeacon = $now
    }
}

function Step-Client {
    foreach ($line in (Read-Lines $script:conn)) { Handle-HostLine $line }
    if ($script:conn.Closed) { End-Chat $Str.RoomClosed }
}

function Stop-Chat {
    try {
        if ($script:isHost) {
            Send-All 'CLOSE'
            if ($script:peers.Count -gt 0) { Start-Sleep -Milliseconds 150 }
            foreach ($peer in @($script:peers)) { try { $peer.Client.Close() } catch { } }
            if ($script:listener) { $script:listener.Stop() }
            if ($script:beacon) { $script:beacon.Close() }
        } elseif ($script:conn) {
            Send-Line $script:conn 'BYE'
            $script:conn.Client.Close()
        }
    } catch { }
    $script:listener = $null
    $script:beacon = $null
    $script:conn = $null
    $script:peers = New-Object System.Collections.ArrayList
}

function Handle-Command([string]$text) {
    switch (($text -split '\s+', 2)[0].ToLower()) {
        '/q' { $script:running = $false }
        '/salir' { $script:running = $false }
        '/lista' {
            $names = if ($script:isHost) { Get-PlayerNames } else { $script:players }
            Write-System ($Str.WhoLine -f @($names).Count, (@($names) -join ', '))
        }
        default { Write-System $Str.CmdUnknown }
    }
}

function Submit-Typed {
    $text = Clean-Text $script:typed 300
    Clear-Input
    $script:typed = ''
    if ($text.Length -eq 0) {
        Show-Input
        return
    }
    if ($text.StartsWith('/')) {
        Handle-Command $text
    } elseif ($script:isHost) {
        Post-Chat $script:me $text
    } else {
        Send-Line $script:conn ('MSG|' + $text)
        Show-Input
    }
}

function Read-Keys {
    while ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'Enter' { Submit-Typed }
            'Backspace' {
                if ($script:typed.Length -gt 0) {
                    Clear-Input
                    $script:typed = $script:typed.Substring(0, $script:typed.Length - 1)
                    Show-Input
                }
            }
            'Escape' {
                Clear-Input
                $script:typed = ''
                Show-Input
            }
            default {
                $ch = $key.KeyChar
                if ([int]$ch -ge 32 -and -not [char]::IsControl($ch) -and $script:typed.Length -lt (Get-InputLimit)) {
                    $script:typed += [string]$ch
                    Write-Host ([string]$ch) -NoNewline
                }
            }
        }
    }
}

function Invoke-Chat($extra = @(), [string]$requested = '') {
    $script:running = $true
    $script:endMessage = $null
    $script:typed = ''
    Clear-Host
    Write-Host ($Str.HeaderRoom -f $script:roomName, $script:hostIp)
    Write-Host $Str.HeaderYou -NoNewline
    Write-Host $script:me -ForegroundColor (Get-NameColor $script:me)
    if ($script:isHost) { Write-Host $Str.HostHint }
    Write-Host $Str.Hints
    Write-Host ''
    Show-Input
    if ($script:isHost) { Write-System $Str.RoomCreated }
    if ($requested.Length -gt 0 -and $requested -cne $script:me) { Write-System ($Str.NameChanged -f $script:me) }
    foreach ($line in $extra) { Handle-HostLine $line }
    while ($script:running) {
        if ($script:isHost) { Step-Host } else { Step-Client }
        Read-Keys
        Start-Sleep -Milliseconds 30
    }
    Write-Host ''
}

function Connect-Peer($room) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $result = $client.BeginConnect([string]$room.Ip, [int]$room.Port, $null, $null)
        if (-not $result.AsyncWaitHandle.WaitOne(3000, $false)) { throw 'timeout' }
        $client.EndConnect($result)
        $client.NoDelay = $true
        return (New-Peer $client)
    } catch {
        try { $client.Close() } catch { }
        return $null
    }
}

function Join-Room($room) {
    Write-Host $Str.Connecting
    $peer = Connect-Peer $room
    if ($null -eq $peer) {
        Show-Notice $Str.ConnectFail
        return
    }
    Send-Line $peer ('HI|' + $script:me)
    $welcome = $null
    $refusal = $null
    $extra = New-Object System.Collections.ArrayList
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline -and -not $welcome -and -not $refusal -and -not $peer.Closed) {
        foreach ($line in (Read-Lines $peer)) {
            if ($welcome) { [void]$extra.Add($line) }
            elseif ($line.StartsWith('WELCOME|')) { $welcome = $line }
            elseif ($line.StartsWith('NO|')) { $refusal = $line }
        }
        Start-Sleep -Milliseconds 50
    }
    if (-not $welcome) {
        try { $peer.Client.Close() } catch { }
        if ($refusal -eq 'NO|full') { Show-Notice $Str.RoomFull }
        elseif ($refusal) { Show-Notice $Str.Rejected }
        else { Show-Notice $Str.NoReply }
        return
    }
    $fields = Split-Fields $welcome 3
    $requested = $script:me
    $script:me = [string]$fields[1]
    $script:roomName = [string]$fields[2]
    $script:isHost = $false
    $script:conn = $peer
    $script:hostIp = [string]$room.Ip
    $script:players = @()
    try { Invoke-Chat $extra $requested } finally { Stop-Chat }
    if ($script:endMessage) { Show-Notice $script:endMessage }
}

function Read-ManualRoom {
    $text = ([string](Read-Host $Str.ManualPrompt)).Trim()
    if ($text.Length -eq 0) { return $null }
    $pieces = $text -split ':'
    $addr = $null
    if (-not [System.Net.IPAddress]::TryParse($pieces[0], [ref]$addr)) {
        Show-Notice $Str.ManualBad
        return $null
    }
    $port = $script:ChatPort
    if ($pieces.Count -gt 1) {
        $parsed = 0
        if ([int]::TryParse($pieces[1], [ref]$parsed) -and $parsed -gt 0 -and $parsed -lt 65536) { $port = $parsed }
    }
    [pscustomobject]@{ Name = $text; Owner = '?'; Ip = $addr.ToString(); Port = $port; Count = 0 }
}

function Start-Join {
    while ($true) {
        Clear-Host
        Write-Host $Str.Searching
        $rooms = @(Find-Rooms 2500)
        Clear-Host
        if ($rooms.Count -eq 0) {
            Write-Host $Str.NoRooms
        } else {
            Write-Host $Str.RoomsHeader
            for ($i = 0; $i -lt $rooms.Count; $i++) {
                $room = $rooms[$i]
                Write-Host ($Str.RoomLine -f ($i + 1), $room.Name, $room.Owner, $room.Count, $room.Ip)
            }
        }
        Write-Host ''
        Write-Host $Str.RoomsKeys
        $choice = ([string](Read-Host $Str.Choose)).Trim()
        if ($choice -ieq 'q') { return }
        if ($choice -ieq 'm') {
            $manual = Read-ManualRoom
            if ($manual) {
                Join-Room $manual
                return
            }
            continue
        }
        $picked = $null
        $number = 0
        if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $rooms.Count) {
            $picked = $rooms[$number - 1]
        } else {
            foreach ($room in $rooms) {
                if ($choice.Length -gt 0 -and $room.Name -ieq $choice) { $picked = $room }
            }
        }
        if ($picked) {
            Join-Room $picked
            return
        }
    }
}

function Start-Host {
    Clear-Host
    $default = 'PC-' + (New-RandomCode 4)
    $roomName = Clean-Name ([string](Read-Host ($Str.RoomPrompt -f $default))) 14
    if ($roomName.Length -eq 0) { $roomName = $default }
    Write-Host $Str.Checking
    $taken = @(Find-Rooms 2300 | ForEach-Object { $_.Name })
    $roomName = Get-UniqueName $roomName $taken

    $listener = $null
    for ($port = $script:ChatPort; $port -lt ($script:ChatPort + 10); $port++) {
        try {
            $candidate = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
            $candidate.Start()
            $listener = $candidate
            $script:hostPort = $port
            break
        } catch { }
    }
    if (-not $listener) {
        Show-Notice $Str.PortError
        return
    }

    $network = Get-NetworkInfo
    $script:listener = $listener
    $script:beacon = [System.Net.Sockets.UdpClient]::new()
    $script:beacon.EnableBroadcast = $true
    $script:beaconTargets = @($network.Targets)
    $script:hostIp = if ($network.Ip) { [string]$network.Ip } else { '?' }
    $script:isHost = $true
    $script:roomName = $roomName
    $script:peers = New-Object System.Collections.ArrayList
    $script:lastBeacon = [DateTime]::MinValue
    try { Invoke-Chat } finally { Stop-Chat }
}

function Ask-Name {
    Clear-Host
    Write-Host $Str.Title
    Write-Host ('=' * $Str.Title.Length)
    Write-Host ''
    $default = $Str.DefaultName + (Get-Random -Minimum 10 -Maximum 99)
    $name = Clean-Name ([string](Read-Host ($Str.AskName + ' [' + $default + ']'))) 12
    if ($name.Length -eq 0) { $name = $default }
    $script:me = $name
}

function Show-Menu {
    Clear-Host
    Write-Host ($Str.Hello -f $script:me) -ForegroundColor (Get-NameColor $script:me)
    Write-Host ''
    Write-Host $Str.MenuHost
    Write-Host $Str.MenuJoin
    Write-Host $Str.MenuQuit
    while ($true) {
        $key = [Console]::ReadKey($true)
        switch ([string]$key.KeyChar) {
            '1' { return 'host' }
            '2' { return 'join' }
            'q' { return 'quit' }
        }
    }
}

Ask-Name
$active = $true
while ($active) {
    switch (Show-Menu) {
        'host' { Start-Host }
        'join' { Start-Join }
        'quit' { $active = $false }
    }
}
Clear-Host
