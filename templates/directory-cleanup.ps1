if ($Args.length -eq 1){
    $target_dir=$Args[0]
    $target_days=7
} elseif ($Args.length -eq 2){
    $target_dir=$Args[0]
    $target_days=$Args[1]
} else {
    Write-Error -Message "Usage: directory-cleanup <path> [days]" -Category InvalidArgument
    exit 1
}

if ($target_days -isnot [int]){
    Write-Error -Message "Invalid value for days: $target_days" -Category InvalidArgument
    exit 1
}

if (Test-Path -PathType Container -Path "$target_dir"){
    echo "Cleaning $target_dir for $target_days days"
    Get-ChildItem -path "$target_dir" -Recurse -Force -File | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-$target_days)} |
      ForEach-Object {
          $_ | Remove-Item -Force
          $_.FullName | Write-Output
      }
# delete directories - this probably needs sorting to remove in right order
#    Get-ChildItem -path "$target_dir" -Recurse -Force |
#      ? {$_.PsIsContainer -eq $True} |
#      ? {$_.getfiles().count -eq 0} |
#      ForEach-Object {
#          $_ | Remove-Item -Force
#
#      }
} else {
    Write-Error -Message "Directory '$target_dir' does not exist" -Category InvalidArgument
    exit 1
}
