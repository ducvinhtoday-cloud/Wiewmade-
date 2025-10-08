# ŋƀ.ps1
# Payload: Consent form + Melting horizontal + Color bands spam + System icons spam
# WARNING: Contains flashing visuals. NOT for people with sensitive eyes.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# P/Invoke GetDC / ReleaseDC
$cs = @'
using System;
using System.Runtime.InteropServices;
public static class NativeMethods {
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
}
'@
Add-Type -TypeDefinition $cs

# -------- CONFIG --------
$totalSec = 80              # total seconds of visual effects
# You asked for a pre-warning form; after OK we run the effects for $totalSec seconds.
$fps = 15
$intervalMs = [int](1000 / $fps)

# -------- Consent Form (blue background, big red text) --------
function Show-ConsentForm {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "GDI Effect Warning"
    $f.StartPosition = "CenterScreen"
    $f.Size = New-Object System.Drawing.Size(640,240)
    $f.FormBorderStyle = "FixedDialog"
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.TopMost = $true
    $f.ShowInTaskbar = $false
    $f.BackColor = [System.Drawing.Color]::FromArgb(220,235,250)  # light blue

    # Big red question
    $lblBig = New-Object System.Windows.Forms.Label
    $lblBig.AutoSize = $false
    $lblBig.Size = New-Object System.Drawing.Size(600,70)
    $lblBig.Location = New-Object System.Drawing.Point(20,10)
    $lblBig.TextAlign = "MiddleCenter"
    $lblBig.Font = New-Object System.Drawing.Font("Segoe UI",24,[System.Drawing.FontStyle]::Bold)
    $lblBig.ForeColor = [System.Drawing.Color]::Red
    $lblBig.Text = "Do you wanna open ŋƀ?"
    $f.Controls.Add($lblBig)

    # Warning smaller text
    $lblWarn = New-Object System.Windows.Forms.Label
    $lblWarn.AutoSize = $false
    $lblWarn.Size = New-Object System.Drawing.Size(600,60)
    $lblWarn.Location = New-Object System.Drawing.Point(20,85)
    $lblWarn.TextAlign = "TopLeft"
    $lblWarn.Font = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Regular)
    $lblWarn.ForeColor = [System.Drawing.Color]::Black
    $lblWarn.Text = "Warning: Not for people with sensitive eyes.`r`nIf eyes are sensitive it is recommended not to open."
    $f.Controls.Add($lblWarn)

    # Buttons: OK and No
    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "OK"
    $btnOK.Size = New-Object System.Drawing.Size(110,36)
    $btnOK.Location = New-Object System.Drawing.Point(360,150)
    $btnOK.BackColor = [System.Drawing.Color]::LightGreen
    $btnOK.Add_Click({ $f.Tag = "ok"; $f.Close() })
    $f.Controls.Add($btnOK)

    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = "No"
    $btnNo.Size = New-Object System.Drawing.Size(110,36)
    $btnNo.Location = New-Object System.Drawing.Point(480,150)
    $btnNo.BackColor = [System.Drawing.Color]::LightCoral
    $btnNo.Add_Click({ $f.Tag = "no"; $f.Close() })
    $f.Controls.Add($btnNo)

    $f.Add_Shown({ $f.Activate() })
    $result = $f.ShowDialog()
    return ($f.Tag -eq "ok")
}

# -------- Abort handling (Ctrl+C) --------
$script:abort = $false
$null = Register-EngineEvent PowerShell.Exiting -Action { $script:abort = $true } | Out-Null

function Safe-Sleep($ms) {
    $t = 0
    while ($t -lt $ms) {
        if ($script:abort) { break }
        Start-Sleep -Milliseconds 50
        $t += 50
    }
}

# -------- Ask consent --------
$consent = Show-ConsentForm
if (-not $consent) {
    Write-Host "User pressed No — exiting without effects."
    return
}

# -------- Setup capture + desktop graphics --------
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$W = $screen.Width; $H = $screen.Height

try {
    $baseBmp = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gcap = [System.Drawing.Graphics]::FromImage($baseBmp)
    $gcap.CopyFromScreen(0,0,0,0,$baseBmp.Size)
    $gcap.Dispose()
} catch {
    Write-Warning "Failed to capture desktop; creating blank base."
    $baseBmp = New-Object System.Drawing.Bitmap $W, $H
    $gf = [System.Drawing.Graphics]::FromImage($baseBmp); $gf.Clear([System.Drawing.Color]::Black); $gf.Dispose()
}

$hdc = [NativeMethods]::GetDC([IntPtr]::Zero)
if ($hdc -eq [IntPtr]::Zero) { throw "Cannot get desktop HDC." }
$g = [System.Drawing.Graphics]::FromHdc($hdc)
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighSpeed
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighSpeed

# load system icons
$icons = @(
    [System.Drawing.SystemIcons]::Warning.ToBitmap(),
    [System.Drawing.SystemIcons]::Error.ToBitmap(),
    [System.Drawing.SystemIcons]::Information.ToBitmap(),
    [System.Drawing.SystemIcons]::Question.ToBitmap()
)
$rand = New-Object System.Random

# -------- EFFECT: Melting horizontal + color bands spam + icons (alpha opaque) --------
function Do-MeltingHorizontal_WithBandsAndIcons($seconds) {
    $end = (Get-Date).AddSeconds($seconds)
    $minH = 8; $maxH = 120
    while (-not $script:abort -and (Get-Date) -lt $end) {
        # clone base each frame
        $frame = $baseBmp.Clone()
        $gf = [System.Drawing.Graphics]::FromImage($frame)

        # shift horizontal strips
        $y = 0
        while ($y -lt $H) {
            $hStrip = $rand.Next($minH, $maxH)
            if ($y + $hStrip -gt $H) { $hStrip = $H - $y }
            $shift = $rand.Next(-120, 120)  # shift left/right
            $srcRect = [System.Drawing.Rectangle]::new(0, $y, $W, $hStrip)
            $destRect = [System.Drawing.Rectangle]::new($shift, $y, $W, $hStrip)
            try { $gf.DrawImage($baseBmp, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel) } catch {}
            $y += $hStrip
        }

        # overlay color bands (you asked "mờ 0" meaning no transparency -> opaque)
        for ($b=0; $b -lt 6; $b++) {
            $bandAlpha = 255    # opaque
            $bandColor = [System.Drawing.Color]::FromArgb($bandAlpha, $rand.Next(256), $rand.Next(256), $rand.Next(256))
            $brush = New-Object System.Drawing.SolidBrush $bandColor
            $by = $rand.Next(0, [Math]::Max(1, $H-40))
            $bh = $rand.Next(20, [Math]::Min(200, $H - $by))
            $gf.FillRectangle($brush, 0, $by, $W, $bh)
            $brush.Dispose()
        }

        # spam icons on the frame
        $iconsPerFrame = 12
        for ($i=0; $i -lt $iconsPerFrame; $i++) {
            $ibmp = $icons[$rand.Next(0,$icons.Count)]
            $ix = $rand.Next(0, [Math]::Max(1, $W - $ibmp.Width))
            $iy = $rand.Next(0, [Math]::Max(1, $H - $ibmp.Height))
            $gf.DrawImage($ibmp, $ix, $iy, $ibmp.Width, $ibmp.Height)
        }

        $gf.Dispose()

        # push to desktop
        try { $g.DrawImage($frame, 0,0, $W, $H) } catch {}
        try { $frame.Dispose() } catch {}

        Safe-Sleep($intervalMs)
    }
}

# -------- EFFECT: Color-bit (loang màu splash) --------
function Do-ColorBit($seconds) {
    $end = (Get-Date).AddSeconds($seconds)
    while (-not $script:abort -and (Get-Date) -lt $end) {
        $count = 50
        for ($i=0; $i -lt $count; $i++) {
            $alpha = $rand.Next(80,200)
            $c = [System.Drawing.Color]::FromArgb($alpha, $rand.Next(256), $rand.Next(256), $rand.Next(256))
            $brush = New-Object System.Drawing.SolidBrush $c
            if ($rand.Next(2) -eq 0) {
                $rw = $rand.Next(30, 380)
                $rh = $rand.Next(30, 380)
                $rx = $rand.Next(0, [Math]::Max(1, $W-$rw))
                $ry = $rand.Next(0, [Math]::Max(1, $H-$rh))
                $g.FillEllipse($brush, $rx, $ry, $rw, $rh)
            } else {
                $rw = $rand.Next(30, 320)
                $rh = $rand.Next(30, 320)
                $rx = $rand.Next(0, [Math]::Max(1, $W-$rw))
                $ry = $rand.Next(0, [Math]::Max(1, $H-$rh))
                $g.FillRectangle($brush, $rx, $ry, $rw, $rh)
            }
            $brush.Dispose()
        }
        Safe-Sleep($intervalMs)
    }
}

# Run sequence: ColorBit -> Melting horizontal+bands+icons -> Melting vertical (shortened)
try {
    # Stage durations: distribute totalSec
    $stage1 = [int]([Math]::Floor($totalSec * 0.30))  # ~30%
    $stage2 = [int]([Math]::Floor($totalSec * 0.50))  # ~50%
    $stage3 = $totalSec - $stage1 - $stage2          # rest

    Write-Host "Running Stage 1 (ColorBit) for $stage1 seconds..."
    Do-ColorBit -seconds $stage1
    if ($script:abort) { throw "Aborted" }

    Write-Host "Running Stage 2 (Melting Horizontal + Bands + Icons) for $stage2 seconds..."
    Do-MeltingHorizontal_WithBandsAndIcons -seconds $stage2
    if ($script:abort) { throw "Aborted" }

    # Optional: simple vertical melting similar approach (reuse horizontal by transposing)
    Write-Host "Running Stage 3 (Melting Vertical approx) for $stage3 seconds..."
    # We'll implement simple vertical shift by rotating/working on transposed coords (fast method: shift columns)
    $endV = (Get-Date).AddSeconds($stage3)
    while (-not $script:abort -and (Get-Date) -lt $endV) {
        $frame = $baseBmp.Clone()
        $gf = [System.Drawing.Graphics]::FromImage($frame)
        $x = 0
        $minW = 8; $maxW = 120
        while ($x -lt $W) {
            $wStrip = $rand.Next($minW, $maxW)
            if ($x + $wStrip -gt $W) { $wStrip = $W - $x }
            $shift = $rand.Next(-120,120)  # vertical shift amount for this column strip
            $srcRect = [System.Drawing.Rectangle]::new($x,0,$wStrip,$H)
            $destRect = [System.Drawing.Rectangle]::new($x,$shift,$wStrip,$H)
            try { $gf.DrawImage($baseBmp, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel) } catch {}
            $x += $wStrip
        }

        # overlay vertical opaque color bands
        for ($b=0; $b -lt 6; $b++) {
            $bandAlpha = 255
            $bandColor = [System.Drawing.Color]::FromArgb($bandAlpha, $rand.Next(256), $rand.Next(256), $rand.Next(256))
            $brush = New-Object System.Drawing.SolidBrush $bandColor
            $bx = $rand.Next(0, [Math]::Max(1,$W-40))
            $bw = $rand.Next(20, [Math]::Min(200, $W - $bx))
            $gf.FillRectangle($brush, $bx, 0, $bw, $H)
            $brush.Dispose()
        }

        # spam icons
        for ($i=0; $i -lt 10; $i++) {
            $ibmp = $icons[$rand.Next(0,$icons.Count)]
            $ix = $rand.Next(0, [Math]::Max(1, $W - $ibmp.Width))
            $iy = $rand.Next(0, [Math]::Max(1, $H - $ibmp.Height))
            $gf.DrawImage($ibmp, $ix, $iy, $ibmp.Width, $ibmp.Height)
        }

        $gf.Dispose()
        try { $g.DrawImage($frame, 0,0,$W,$H) } catch {}
        try { $frame.Dispose() } catch {}
        Safe-Sleep($intervalMs)
    }

} catch {
    Write-Warning "Interrupted or error: $_"
} finally {
    # restore desktop
    try { $g.DrawImage($baseBmp, 0,0, $W, $H) } catch {}
    Start-Sleep -Milliseconds 200

    # cleanup
    try { foreach ($b in $icons) { if ($b -ne $null) { $b.Dispose() } } } catch {}
    try { if ($g -ne $null) { $g.Dispose() } } catch {}
    try { if ($hdc -ne $null -and $hdc -ne [IntPtr]::Zero) { [NativeMethods]::ReleaseDC([IntPtr]::Zero,$hdc) } } catch {}
    try { if ($baseBmp -ne $null) { $baseBmp.Dispose() } } catch {}
    try { Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue } catch {}
    Write-Host "Done — desktop restored. If artifacts remain press F5."
}
