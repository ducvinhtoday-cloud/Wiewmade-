' save file with .vbs extension
Option Explicit

Dim shell, resp, i

Set shell = CreateObject("WScript.Shell")

' Hiển thị MsgBox: "continue", icon warning, just OK button, leave title blank 
resp = MsgBox("continue", vbOKOnly + vbExclamation, "")

If resp = vbOK Then
    For i = 1 To 5
        shell.Run "calc.exe"
        ' Optional: Do not select too quickly to avoid causing lag 
        WScript.Sleep 200
    Next
End If

Set shell = Nothing
