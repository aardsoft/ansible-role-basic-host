Set objArgs = WScript.Arguments
Dim serviceName, serviceBinary, distribution
Dim commandString

If WScript.Arguments.Count = 2 Then
   distribution=objArgs(0)
   serviceName=objArgs(1)
   serviceBinary=objArgs(1)
ElseIf Wscript.Arguments.Count = 3 Then
   distribution=objArgs(0)
   serviceName=objArgs(1)
   serviceBinary=objArgs(2)
Else
  WScript.Echo "Wrong number of arguments"
  WScript.Quit
End If

If distribution = "default" Then
  commandString="wsl.exe -u root /usr/sbin/wsl-simpleservice " & serviceName & " " & serviceBinary
Else
  commandString="wsl.exe -u root -d " & distribution & " /usr/sbin/wsl-simpleservice " & serviceName & " " & serviceBinary
End If
WScript.Echo commandString

Set WshShell = CreateObject("WScript.Shell")
WshShell.Run commandString, 0
Set WshShell = Nothing