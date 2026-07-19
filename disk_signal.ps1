Set-PSDebug -Off
Add-Type -AssemblyName PresentationFramework

function Get-SizeGB($bytes) {
    [math]::Round($bytes / 1GB, 2)
}

function Get-FileCategory($file) {

    $ext = if ($file.Extension) {
        $file.Extension.ToLower()
    } else {
        ""
    }

    switch ($ext) {

        ".jpg"  { "Images" }
        ".jpeg" { "Images" }
        ".png"  { "Images" }
        ".gif"  { "Images" }

        ".mp4"  { "Video" }
        ".mov"  { "Video" }
        ".mkv"  { "Video" }

        ".mp3"  { "Audio" }
        ".wav"  { "Audio" }

        ".db"   { "Database" }
        ".sqlite" { "Database" }

        default {

            # 🔥 fallback для Signal (важливо!)
            if ($file.Length -gt 50MB) {
                return "Large Media"
            }

            return "Other"
        }
    }
}


# --- Signal analysis ---

$signalStats = @{}
$totalSize = 0

$signalPath = Join-Path $env:APPDATA "Signal"


# 🧠 якщо не знайдено — просто вихід без помилок
if (-not $signalPath) {
    $signalPath = $null
    return
}

# 📁 отримуємо файли
$files = Get-ChildItem $signalPath -Recurse -File -ErrorAction SilentlyContinue

if (-not $files) {
    return
}

$signalExists = $files -and $files.Count -gt 0

# 📊 загальний розмір
$totalSize = [int64](($files | Measure-Object Length -Sum).Sum)

# 📦 групування
foreach ($f in $files) {

    $cat = Get-FileCategory $f

    if (-not $signalStats.ContainsKey($cat)) {
        $signalStats[$cat] = [int64]0
    }

    $signalStats[$cat] += [int64]$f.Length
}

# =========================
# DATA
# =========================
$drives = Get-PSDrive -PSProvider FileSystem | ForEach-Object {

    $used = $_.Used
    $free = $_.Free
    $total = $used + $free

    $percent = if ($total -gt 0) {
        [math]::Round(($used / $total) * 100, 1)
    } else { 0 }

    [PSCustomObject]@{
        Name = "Disk " + $_.Name
        'UsedGB'      = Get-SizeGB $used
        'FreeGB'      = Get-SizeGB $free
        'TotalGB'     = Get-SizeGB $total
        'UsedPercent' = $percent
    }
}

# =========================
# UI (MINIMAL SAFE XAML)
# =========================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Утілита перевірок пінгів, диска та Signal V2" Height="740" Width="600" WindowStartupLocation="CenterScreen" ResizeMode="NoResize">

    <Grid Margin="10">

        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="130"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
       
        <TextBlock Grid.Row="0" FontSize="30" FontWeight="Bold" Margin="0,0,0,10">
            Аналіз використання дисків
        </TextBlock>
        
        <DataGrid Grid.Row="1" Name="DiskGrid" AutoGenerateColumns="False" FontSize="25"
                  IsReadOnly="True" CanUserAddRows="False">

                  <DataGrid.Columns>
    <DataGridTextColumn Header="Диск" Binding="{Binding Name}" />
    <DataGridTextColumn Header="Вик-но GB" Binding="{Binding UsedGB}" />
    <DataGridTextColumn Header="Вільно GB" Binding="{Binding FreeGB}" />
    <DataGridTextColumn Header="Загалом GB" Binding="{Binding TotalGB}" />
    <DataGridTextColumn Header="%" Binding="{Binding UsedPercent}" />
</DataGrid.Columns>

            </DataGrid>


        <StackPanel Grid.Row="2">
            <TextBlock FontSize="30" FontWeight="Bold" Margin="0,10,0,5">
                Аналіз сховища додатка Signal
            </TextBlock>

            <TextBlock FontSize="20" Name="SignalTotal"/>
            <ListBox FontSize="20" Name="SignalList"/>

            <Button Name="ClearLargeMediaBtn" FontSize="30"  Content="Очистити великі і кеш Signal" Height="45" Margin="0,10,0,0"/>
            <Button Name="ClearOldFilesBtn" FontSize="30" Content="Очистити файли старші за 30 днів" Height="45" Margin="0,5,0,0"/>

            <Button Name="PingBtn"
        FontSize="30"
        Content="Перевірка пінгів"
        Height="45"
        Margin="0,5,0,0"/>

<ProgressBar Name="PingProgress"
             Height="20"
             Margin="0,5,0,0"
             Visibility="Collapsed"
             Minimum="0"
             Maximum="16"
             Value="0"/>

<TextBlock Name="PingStatus"
           FontSize="16"
           Margin="0,5,0,0"
           Text=""/>

<Border Name="PingBorder"
        Margin="0,5,0,0"
        Padding="8"
        Background="LightGray">

    <TextBlock Name="PingResult"
               FontSize="20"
               Text="Пінг не перервірено"/>

</Border>

            <Button Name="CloseBtn" FontSize="30" Content="Закрити" Height="45" Margin="0,5,0,0"/>

        </StackPanel>
    </Grid>
</Window>
"@

# =========================
# LOAD WINDOW
# =========================
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$grid = $window.FindName("DiskGrid")

# force real array
$drives = @($drives)

$grid.ItemsSource = $null
$grid.ItemsSource = $drives

# =========================
# COLOR LOGIC (WORKING)
# =========================
$grid.Add_LoadingRow({
    param($sender, $e)

    $item = $e.Row.DataContext

    if (-not $item) {
        return
    }

    $p = $item.UsedPercent

    if ($p -ge 85) {
        $e.Row.Background = "LightCoral"   # 🔴
    }
    elseif ($p -ge 70) {
        $e.Row.Background = "Khaki"        # 🟡
    }
    else {
        $e.Row.Background = "LightGreen"   # 🟢
    }
})

$signalTotal = $window.FindName("SignalTotal")
$signalList = $window.FindName("SignalList")
$closeBtn = $window.FindName("CloseBtn")
$clearBtn = $window.FindName("ClearLargeMediaBtn")
$oldBtn = $window.FindName("ClearOldFilesBtn")

$pingBtn = $window.FindName("PingBtn")
$pingProgress = $window.FindName("PingProgress")
$pingBorder = $window.FindName("PingBorder")
$pingResult = $window.FindName("PingResult")

if ($signalExists) {
    $signalTotal.Text = "Розмір папки Signal: " + (Get-SizeGB $totalSize) + " GB"
    $signalTotal.FontWeight = "Bold"

    foreach ($k in $signalStats.Keys) {

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = "$k : $(Get-SizeGB $signalStats[$k]) GB"

    if ($k -eq "Large Media") {
        $tb.FontWeight = "Bold"
        $tb.Foreground = "Red"
    }

    [void]$signalList.Items.Add($tb)
}
} else {
    $signalTotal.Text = "Signal не знайдено"
}

$closeBtn.Add_Click({
    $window.Close()
})

$clearBtn.Add_Click({

    $result = [System.Windows.MessageBox]::Show(
        "Ви впевнені, що хочете видалити файли великі і кеш?",
        "Підтвердження дії",
        "YesNo",
        "Warning"
    )

    if ($result -ne "Yes") {
        return
    }

    if (-not (Test-Path $signalPath)) {
        return
    }

    $files = Get-ChildItem $signalPath -Recurse -File -ErrorAction SilentlyContinue

    foreach ($f in $files) {

        # Спочатку видаляємо все з attachments.noindex
        if ($f.FullName -match "\\attachments\.noindex\\") {
            try {
                Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            } catch {}
            continue
        }

        $cat = Get-FileCategory $f

        if ($cat -eq "Large Media") {
            try {
                Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            } catch {}
        }
    }

    # refresh stats
    $signalStats.Clear()

    $files = Get-ChildItem $signalPath -Recurse -File -ErrorAction SilentlyContinue

    foreach ($f in $files) {
        $cat = Get-FileCategory $f
        if (-not $signalStats[$cat]) { $signalStats[$cat] = 0 }
        $signalStats[$cat] += $f.Length
    }

    # refresh UI
    $signalList.Items.Clear()

    foreach ($k in $signalStats.Keys) {

        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "$k : $(Get-SizeGB $signalStats[$k]) GB"

        if ($k -eq "Large Media") {
            $tb.FontWeight = "Bold"
            $tb.Foreground = "Red"
        }

        $signalList.Items.Add($tb)
    }

})

$oldBtn.Add_Click({
    
    $result = [System.Windows.MessageBox]::Show(
        "Ви впевнені, що хочете видалити файли старші за 30 днів?",
        "Підтвердження дії",
        "YesNo",
        "Warning"
    )

    if ($result -ne "Yes") {
        return
    }

    if (-not (Test-Path $signalPath)) {
        return
    }

    $limitDate = (Get-Date).AddDays(-30)

    $files = Get-ChildItem $signalPath -Recurse -File -ErrorAction SilentlyContinue

    foreach ($f in $files) {

        if ($f.LastWriteTime -lt $limitDate) {
            try {
                Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            } catch {}
        }
    }

    # refresh stats
    $signalStats.Clear()

    $files = Get-ChildItem $signalPath -Recurse -File -ErrorAction SilentlyContinue

    foreach ($f in $files) {
        $cat = Get-FileCategory $f
        if (-not $signalStats[$cat]) { $signalStats[$cat] = 0 }
        $signalStats[$cat] += $f.Length
    }

    # refresh UI
    $signalList.Items.Clear()

    foreach ($k in $signalStats.Keys) {

        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = "$k : $(Get-SizeGB $signalStats[$k]) GB"

        if ($k -eq "Large Media") {
            $tb.FontWeight = "Bold"
            $tb.Foreground = "Red"
        }

        $signalList.Items.Add($tb)
    }

})

$pingBtn.Add_Click({

    $pingProgress.Visibility = "Visible"
    $pingProgress.Minimum = 0
    $pingProgress.Maximum = 16
    $pingProgress.Value = 0

    $pingStatus = $window.FindName("PingStatus")

    $pingBorder.Background = "LightGray"
    $pingResult.Text = "Перевірка..."

    $clearBtn.IsEnabled = $false
    $oldBtn.IsEnabled = $false
    $closeBtn.IsEnabled = $false
    $pingBtn.IsEnabled = $false

    $targets = @("1.1.1.1","8.8.8.8")

    $all = @()
    $step = 0

    foreach ($t in $targets) {
        for ($i = 1; $i -le 8; $i++) {

            $step++
            $pingProgress.Value = $step
            $pingStatus.Text = "$t ($i/8)"

            # 💥 ВАЖЛИВО: примусовий рендер UI
            $window.Dispatcher.Invoke([action]{}, "Render")

            try {
                $r = Test-Connection -ComputerName $t -Count 1 -ErrorAction Stop
                $ms = $r.ResponseTime
            }
            catch {
                $ms = 999
            }

            $all += $ms

            Start-Sleep -Milliseconds 200
        }
    }

    $line = ($all -join ", ")
    $avg = [math]::Round(($all | Measure-Object -Average).Average, 1)

    $pingResult.Text = "$line`nСередній пінг: $avg ms"

    $pingProgress.Visibility = "Collapsed"

    if ($avg -lt 30) {
        $pingBorder.Background = "LightGreen"
    }
    elseif ($avg -lt 70) {
        $pingBorder.Background = "Khaki"
    }
    else {
        $pingBorder.Background = "LightCoral"
    }

    $clearBtn.IsEnabled = $true
    $oldBtn.IsEnabled = $true
    $closeBtn.IsEnabled = $true
    $pingBtn.IsEnabled = $true
})


# =========================
# SHOW
# =========================
$window.ShowDialog()  | Out-Null