Set objArgs = WScript.Arguments
Dim serviceName, serviceBinary, distribution
Dim commandString

If WScript.Arguments.Count = 1 Then
   distribution=objArgs(0)
Else
  WScript.Echo "Wrong number of arguments"
  WScript.Quit
End If

If distribution = "default" Then
  commandString="wsl.exe -u root /usr/sbin/wsl-simple-init"
Else
  commandString="wsl.exe -u root -d " & distribution & " /usr/sbin/wsl-simple-init"
End If
WScript.Echo commandString

Set WshShell = CreateObject("WScript.Shell")
WshShell.Run commandString, 0
Set WshShell = Nothing