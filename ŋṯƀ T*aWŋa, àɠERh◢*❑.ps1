# payload_12_0.ps1
# Payload 12.0 — User consent + 3 GDI effects on desktop
# WARNING: contains flashing visuals. Do NOT run if you or others are sensitive to flicker/epilepsy.

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

function Show-ConsentForm {
    # returns $true if Yes pressed, $false if No
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "GDI Effect Warning"
    $f.StartPosition = "CenterScreen"
    $f.Size = New-Object System.Drawing.Size(520,220)
    $f.FormBorderStyle = "FixedDialog"
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.TopMost = $true
    $f.ShowInTaskbar = $false
    $f.BackColor = [System.Drawing.Color]::FromArgb(230, 240, 250) # soft blue background

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.AutoSize = $false
    $lbl.Size = New-Object System.Drawing.Size(480,110)
    $lbl.Location = New-Object System.Drawing.Point(15,10)
    $lbl.TextAlign = "MiddleLeft"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Regular)
    $lbl.Text = "Hey, continue?`r`n`r`nWarning: GDI effects may cause eye strain and are NOT for eyes sensitive to flicker.`r`nWarning: Works fast on Windows 7."
    $f.Controls.Add($lbl)

    $btnYes = New-Object System.Windows.Forms.Button
    $btnYes.Text = "Yes"
    $btnYes.Size = New-Object System.Drawing.Size(100,34)
    $btnYes.Location = New-Object System.Drawing.Point(290,130)
    $btnYes.BackColor = [System.Drawing.Color]::LightGreen
    $btnYes.Add_Click({ $f.Tag = "yes"; $f.Close() })
    $f.Controls.Add($btnYes)

    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = "No"
    $btnNo.Size = New-Object System.Drawing.Size(100,34)
    $btnNo.Location = New-Object System.Drawing.Point(395,130)
    $btnNo.BackColor = [System.Drawing.Color]::LightCoral
    $btnNo.Add_Click({ $f.Tag = "no"; $f.Close() })
    $f.Controls.Add($btnNo)

    $f.Add_Shown({ $f.Activate() })
    [void] $f.ShowDialog()

    return ($f.Tag -eq "yes")
}

# --- Config: durations (seconds) ---
$durColorBit = 20
$durMeltingH = 20
$durMeltingV = 20
$fps = 12
$intervalMs = [int](1000/$fps)

# --- Ask user ---
$consent = Show-ConsentForm
if (-not $consent) {
    Write-Host "User chose No — exiting. No effects started."
    return
}

# --- Setup for desktop drawing & capture background ---
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$W = $screen.Width; $H = $screen.Height

# capture background for restore
try {
    $baseBmp = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gcap = [System.Drawing.Graphics]::FromImage($baseBmp)
    $gcap.CopyFromScreen(0,0,0,0,$baseBmp.Size)
    $gcap.Dispose()
} catch {
    Write-Warning "Cannot capture desktop background: $_"
    # fallback: create blank
    $baseBmp = New-Object System.Drawing.Bitmap $W, $H
    $gFill = [System.Drawing.Graphics]::FromImage($baseBmp)
    $gFill.Clear([System.Drawing.Color]::Black)
    $gFill.Dispose()
}

# get desktop HDC & Graphics
$hdc = [NativeMethods]::GetDC([IntPtr]::Zero)
if ($hdc -eq [IntPtr]::Zero) { throw "Cannot get desktop HDC." }
$g = [System.Drawing.Graphics]::FromHdc($hdc)
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighSpeed
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighSpeed

$rand = New-Object System.Random

# helper: safe draw and sleep with cancellation via Ctrl+C
$script:abort = $false
$null = Register-EngineEvent PowerShell.Exiting -Action { $script:abort = $true } | Out-Null

function Safe-Sleep($ms) {
    $t = [int]0
    while ($t -lt $ms) {
        if ($script:abort) { break }
        Start-Sleep -Milliseconds 50
        $t += 50
    }
}

# EFFECT 1: Color bit — loang màu / splash
function Effect-ColorBit {
    param($seconds)
    $end = (Get-Date).AddSeconds($seconds)
    while (-not $script:abort -and (Get-Date) -lt $end) {
        # draw many semi-transparent circles/rects across desktop
        $count = 40
        for ($i=0; $i -lt $count; $i++) {
            $alpha = $rand.Next(60,130)  # semi-transparent
            $c = [System.Drawing.Color]::FromArgb($alpha, $rand.Next(256), $rand.Next(256), $rand.Next(256))
            $brush = New-Object System.Drawing.SolidBrush $c
            if ($rand.Next(2) -eq 0) {
                # circle
                $rw = $rand.Next(40, 350)
                $rh = $rand.Next(40, 350)
                $rx = $rand.Next(0, [Math]::Max(1,$W-$rw))
                $ry = $rand.Next(0, [Math]::Max(1,$H-$rh))
                $g.FillEllipse($brush, $rx, $ry, $rw, $rh)
            } else {
                # rectangle splash
                $rw = $rand.Next(30, 300)
                $rh = $rand.Next(30, 300)
                $rx = $rand.Next(0, [Math]::Max(1,$W-$rw))
                $ry = $rand.Next(0, [Math]::Max(1,$H-$rh))
                $g.FillRectangle($brush, $rx, $ry, $rw, $rh)
            }
            $brush.Dispose()
        }
        Safe-Sleep($intervalMs)
    }
}

# EFFECT 2: Melting horizontal + color bands
function Effect-MeltingHorizontal {
    param($seconds)
    # We'll create frames by shifting horizontal strips of the captured base with random offsets,
    # and overlay colored translucent bands for 'spam color bands'.
    $end = (Get-Date).AddSeconds($seconds)

    # choose strip height range
    $minH = 6; $maxH = 80
    while (-not $script:abort -and (Get-Date) -lt $end) {
        # create working bitmap clone from base
        $frame = $baseBmp.Clone()
        $gf = [System.Drawing.Graphics]::FromImage($frame)

        # cut into horizontal strips and draw shifted
        $y = 0
        while ($y -lt $H) {
            $hStrip = [Math]::Min($maxH, [Math]::Max($minH, [int]($rand.Next($minH, $maxH))))
            if ($y + $hStrip -gt $H) { $hStrip = $H - $y }
            $shift = $rand.Next(-60, 60)  # shift left/right
            $srcRect = [System.Drawing.Rectangle]::new(0, $y, $W, $hStrip)
            $destRect = [System.Drawing.Rectangle]::new($shift, $y, $W, $hStrip)
            try {
                $gf.DrawImage($baseBmp, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
            } catch {}
            $y += $hStrip
        }

        # overlay a few translucent color bands
        for ($b=0; $b -lt 6; $b++) {
            $bandAlpha = $rand.Next(40,120)
            $bandColor = [System.Drawing.Color]::FromArgb($bandAlpha, $rand.Next(256), $rand.Next(256), $rand.Next(256))
            $brush = New-Object System.Drawing.SolidBrush $bandColor
            $by = $rand.Next(0, [Math]::Max(1, $H-40))
            $bh = $rand.Next(20, [Math]::Min(200, $H - $by))
            $gf.FillRectangle($brush, 0, $by, $W, $bh)
            $brush.Dispose()
        }

        $gf.Dispose()

        # push to desktop
        try { $g.DrawImage($frame, 0,0, $W, $H) } catch {}
        try { $frame.Dispose() } catch {}

        Safe-Sleep($intervalMs)
    }
}

# EFFECT 3: Melting vertical
function Effect-MeltingVertical {
    param($seconds)
    $end = (Get-Date).AddSeconds($seconds)

    $minW = 6; $maxW = 80
    while (-not $script:abort -and (Get-Date) -lt $end) {
        $frame = $baseBmp.Clone()
        $gf = [System.Drawing.Graphics]::FromImage($frame)

        # vertical strips moved up/down
        $x = 0
        while ($x -lt $W) {
            $wStrip = [Math]::Min($maxW, [Math]::Max($minW, [int]($rand.Next($minW, $maxW))))
            if ($x + $wStrip -gt $W) { $wStrip = $W - $x }
            $shift = $rand.Next(-60, 60)  # shift up/down by shift pixels (applied as dest y offset)
            $srcRect = [System.Drawing.Rectangle]::new($x, 0, $wStrip, $H)
            $destRect = [System.Drawing.Rectangle]::new($x, $shift, $wStrip, $H)
            try {
                $gf.DrawImage($baseBmp, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
            } catch {}
            $x += $wStrip
        }

        # overlay vertical color streaks
        for ($b=0; $b -lt 6; $b++) {
            $bandAlpha = $rand.Next(40,120)
            $bandColor = [System.Drawing.Color]::FromArgb($bandAlpha, $rand.Next(256), $rand.Next(256), $rand.Next(256))
            $brush = New-Object System.Drawing.SolidBrush $bandColor
            $bx = $rand.Next(0, [Math]::Max(1, $W-40))
            $bw = $rand.Next(20, [Math]::Min(200, $W - $bx))
            $gf.FillRectangle($brush, $bx, 0, $bw, $H)
            $brush.Dispose()
        }

        $gf.Dispose()
        try { $g.DrawImage($frame, 0,0, $W, $H) } catch {}
        try { $frame.Dispose() } catch {}

        Safe-Sleep($intervalMs)
    }
}

# Run effects sequentially. If user aborts (Ctrl+C), the loop will break and finally will restore.
try {
    Write-Host "Starting ColorBit ($durColorBit s)..."
    Effect-ColorBit -seconds $durColorBit
    if ($script:abort) { throw "Aborted" }

    Write-Host "Starting Melting Horizontal ($durMeltingH s)..."
    Effect-MeltingHorizontal -seconds $durMeltingH
    if ($script:abort) { throw "Aborted" }

    Write-Host "Starting Melting Vertical ($durMeltingV s)..."
    Effect-MeltingVertical -seconds $durMeltingV
    if ($script:abort) { throw "Aborted" }
}
catch {
    Write-Warning "Effect interrupted or error: $_"
}
finally {
    # restore original desktop
    try {
        $g.DrawImage($baseBmp, 0,0, $W, $H)
        Start-Sleep -Milliseconds 200
    } catch {
        Write-Warning "Restore failed: $_"
    }

    # cleanup
    try { if ($g -ne $null) { $g.Dispose() } } catch {}
    try { if ($hdc -ne $null -and $hdc -ne [IntPtr]::Zero) { [NativeMethods]::ReleaseDC([IntPtr]::Zero,$hdc) } } catch {}
    try { if ($baseBmp -ne $null) { $baseBmp.Dispose() } } catch {}

    # unregister abort listener (best-effort)
    try { Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue } catch {}

    Write-Host "Done. Desktop restored (if any artifacts remain, press F5)."
}
