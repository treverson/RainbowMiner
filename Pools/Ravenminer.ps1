﻿using module ..\Include.psm1

param(
    [PSCustomObject]$Wallets,
    [alias("WorkerName")]
    [String]$Worker,
    [TimeSpan]$StatSpan,
    [String]$DataWindow = "avg",
    [Bool]$InfoOnly = $false,
    [Bool]$AllowZero = $false,
    [String]$StatAverage = "Minute_10"
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$Pool_Request = [PSCustomObject]@{}

$Success = $true
try {
    if (-not ($Pool_Request = Invoke-RestMethodAsync "https://ravenminer.com/api/status" -tag $Name)){throw}
}
catch {
    if ($Error.Count){$Error.RemoveAt(0)}
    $Success = $false
}

if (-not $Success) {
    $Success = $true
    try {
        $Pool_Request = Invoke-GetUrl "https://ravenminer.com/site/current_results" -method "WEB"
        $Value_Group = ([regex]'data="([\d\.]+?)"').Matches($Pool_Request.Content).Groups | Where-Object Name -eq 1
        if (-not ($Value = $Value_Group | Select-Object -Last 1 -ExpandProperty Value)){throw}
        $Hashrate = $Value_Group | Select-Object -First 1 -ExpandProperty Value
        $Pool_Request = [PSCustomObject]@{'x16r'=[PSCustomObject]@{actual_last24h = $Value;hashrate = $Hashrate;fees = 0.5;name = "x16r";port = 1111}}
        $DataWindow = "actual_last24h"
    }
    catch {
        if ($Error.Count){$Error.RemoveAt(0)}
        $Success = $false
    }
}

if (-not $Success) {
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}

if (($Pool_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -lt 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

try {
    if (-not ($PoolCoins_Request = Invoke-RestMethodAsync "https://ravenminer.com/api/currencies" -tag $Name)){throw}
}
catch {
    if ($Error.Count){$Error.RemoveAt(0)}
    $Success = $false
}

if (-not $Success) {
    $Success = $true
    try {
        $PoolCoins_Request = Invoke-GetUrl "https://ravenminer.com/site/history_results" -method "WEB"
        $Value_Content = $PoolCoins_Request.Content -split "</thead>" | Select-Object -Last 1
        $Value_Content = $Value_Content -split "</tr>" | Select-Object -First 1        
        $Value_Content = ([regex]">([\d\.]+?)<").Matches($Value_Content)
        if ($Value_Content.Count -ge 2) {
            $PoolCoins_Request = [PSCustomObject]@{RVN=[PSCustomObject]@{"24h_blocks" = $Value_Content[1].Groups[1].Value}}
        }
    }
    catch {
        if ($Error.Count){$Error.RemoveAt(0)}
        $Success = $false
    }
}

$Pool_Coin = "Ravencoin"
$Pool_Currency = "RVN"
$Pool_Host = "ravenminer.com"
$Pool_Region = Get-Region "us"

$Pool_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$Pool_Request.$_.actual_last24h -gt 0 -or $InfoOnly -or $AllowZero} | ForEach-Object {
    $Pool_Algorithm = $Pool_Request.$_.name
    $Pool_Algorithm_Norm = Get-Algorithm $Pool_Algorithm
    $Pool_PoolFee = [Double]$Pool_Request.$_.fees
    $Pool_User = $Wallets.$Pool_Currency
    $Pool_Port = 6666

    $Pool_Factor = 1

    $Pool_TSL = if ($PoolCoins_Request) {$PoolCoins_Request.$Pool_CoinSymbol.timesincelast}else{$null}
    $Pool_BLK = $PoolCoins_Request.$Pool_Currency."24h_blocks"

    if (-not $InfoOnly) {
        $NewStat = $false; if (-not (Test-Path "Stats\Pools\$($Name)_$($Pool_Algorithm_Norm)_Profit.txt")) {$NewStat = $true; $DataWindow = "estimate_last24h"}
        $Pool_Price = Get-YiiMPValue $Pool_Request.$_ -DataWindow $DataWindow -Factor $Pool_Factor
        $Stat = Set-Stat -Name "$($Name)_$($Pool_Algorithm_Norm)_Profit" -Value $Pool_Price -Duration $(if ($NewStat) {New-TimeSpan -Days 1} else {$StatSpan}) -ChangeDetection $false -ErrorRatio 0.000 -HashRate $Pool_Request.$_.hashrate -BlockRate $Pool_BLK -Quiet
    }

    if ($Pool_User -or $InfoOnly) {
        [PSCustomObject]@{
            Algorithm     = $Pool_Algorithm_Norm
            CoinName      = $Pool_Coin
            CoinSymbol    = $Pool_Currency
            Currency      = $Pool_Currency
            Price         = $Stat.$StatAverage #instead of .Live
            StablePrice   = $Stat.Week
            MarginOfError = $Stat.Week_Fluctuation
            Protocol      = "stratum+tcp"
            Host          = $Pool_Host
            Port          = $Pool_Port
            User          = $Pool_User
            Pass          = "{workername:$Worker},c=$Pool_Currency{diff:,d=`$difficulty}"
            Region        = $Pool_Region
            SSL           = $false
            Updated       = $Stat.Updated
            PoolFee       = $Pool_PoolFee
            DataWindow    = $DataWindow
            Workers       = $Pool_Request.$_.workers
            Hashrate      = $Stat.HashRate_Live
            BLK           = $Stat.BlockRate_Average
            TSL           = $Pool_TSL
            ErrorRatio    = $Stat.ErrorRatio_Average
        }
    }
}
