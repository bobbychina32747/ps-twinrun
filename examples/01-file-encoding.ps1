$word = -join [char[]](0x4E2D, 0x6587)
$word | Out-File -LiteralPath 'message.txt'
