Write-Output ('argc = ' + $args.Count)
for ($i = 0; $i -lt $args.Count; $i++) {
    Write-Output ('argv[{0}] = <{1}>' -f $i, $args[$i])
}
