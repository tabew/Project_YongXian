# 批量跑单元测试并汇总：每个测试带超时，避免个别渲染型测试在无头模式卡死。
# 用法： pwsh -File tools/run_tests.ps1
param(
	[string[]]$Only = @(),
	[int]$TimeoutSeconds = 90
)

$godot = 'E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
# 这两个测试需要真实窗口，无头模式下会挂起，默认跳过。
$skip = @('test_give_monster', 'test_hit_flash_render')

$names = if ($Only.Count -gt 0) { $Only } else {
	Get-ChildItem 'tests\*.gd' | ForEach-Object { $_.BaseName } | Where-Object { $skip -notcontains $_ }
}

$outFile = Join-Path $env:TEMP 'gdtest_stdout.txt'
$errFile = Join-Path $env:TEMP 'gdtest_stderr.txt'
$results = @()

foreach ($name in $names) {
	$p = Start-Process -FilePath $godot -ArgumentList @('--headless', '--path', '.', '--script', "res://tests/$name.gd") -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
	$finished = $p.WaitForExit($TimeoutSeconds * 1000)
	if (-not $finished) { $p.Kill(); $p.WaitForExit() }

	$raw = ''
	foreach ($file in @($outFile, $errFile)) {
		if (Test-Path $file) { $raw += [System.IO.File]::ReadAllText($file) }
	}
	# 新式测试打印 "N checks, N failures"；老式测试打印 "XXX_CHECK ...=true" 与 "XXX_RESULT=bool"。
	$match = [regex]::Match($raw, '(\d+) checks, (\d+) failures')
	if ($match.Success) {
		$checks = [int]$match.Groups[1].Value
		$failures = [int]$match.Groups[2].Value
	} else {
		$checks = ([regex]::Matches($raw, '(?m)^[A-Z_]+_CHECK ')).Count
		$resultMatch = [regex]::Match($raw, '(?m)^[A-Z_]+_RESULT=(true|false)')
		$legacyPassed = [regex]::IsMatch($raw, '(?m)^[A-Z_]+_(TESTS_)?PASSED')
		if ($resultMatch.Success) {
			$failures = if ($resultMatch.Groups[1].Value -eq 'true') { 0 } else { 1 }
		} elseif ($legacyPassed) {
			$failures = 0
		} else {
			$failures = -1
		}
	}
	$results += [pscustomobject]@{
		Test     = $name
		Checks   = $checks
		Failures = $failures
		TimedOut = -not $finished
	}
}

$results | Sort-Object Test | Format-Table -AutoSize | Out-String
"汇总：{0} 个测试，{1} 个无结果，{2} 个失败项" -f $results.Count,
	(($results | Where-Object { $_.Failures -lt 0 }).Count),
	(($results | Where-Object { $_.Failures -gt 0 }).Count)
