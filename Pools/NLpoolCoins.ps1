﻿using module ..\Include.psm1

param(
    [PSCustomObject]$Wallets,
    [alias("WorkerName")]
    [String]$Worker,
    [TimeSpan]$StatSpan,
    [String]$DataWindow = "estimate_current",
    [Bool]$InfoOnly = $false,
    [Bool]$AllowZero = $false,
    [String]$StatAverage = "Minute_10"
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$Pool_Request = [PSCustomObject]@{}
$PoolCoins_Request = [PSCustomObject]@{}


try {
    $PoolCoins_Request = Invoke-RestMethodAsync "http://www.nlpool.nl/api/currencies" -tag $Name
}
catch {
    if ($Error.Count){$Error.RemoveAt(0)}
    Write-Log -Level Warn "Pool currencies API ($Name) has failed. "
    return
}

if (($PoolCoins_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Warn "Pool API ($Name) returned nothing. "
    return
}

try {
    $Pool_Request = Invoke-RestMethodAsync "http://www.nlpool.nl/api/status" -tag $Name
}
catch {
    if ($Error.Count){$Error.RemoveAt(0)}
    Write-Log -Level Warn "Pool API ($Name) has failed. "
}

[hashtable]$Pool_Algorithms = @{}
[hashtable]$Pool_Coins = @{}
[hashtable]$Pool_RegionsTable = @{}

$Pool_Regions = @("us")
$Pool_Regions | Foreach-Object {$Pool_RegionsTable.$_ = Get-Region $_}
$Pool_Currencies = @("BTC","LTC") + @($Wallets.PSObject.Properties.Name | Select-Object) + @($PoolCoins_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Foreach-Object {if ($PoolCoins_Request.$_.symbol -eq $null){$_} else {$PoolCoins_Request.$_.symbol}}) | Select-Object -Unique | Where-Object {$Wallets.$_ -or $InfoOnly}

$Pool_Host = "mine.nlpool.nl"

$PoolCoins_Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Select-Object -ExpandProperty Name | Where-Object {$PoolCoins_Request.$_.hashrate -gt 0 -or $AllowZero -or $InfoOnly} |ForEach-Object {
    $Pool_CoinSymbol = $_

    $Pool_Port = $PoolCoins_Request.$Pool_CoinSymbol.port
    $Pool_Algorithm = $PoolCoins_Request.$Pool_CoinSymbol.algo
    if (-not $Pool_Algorithms.ContainsKey($Pool_Algorithm)) {$Pool_Algorithms.$Pool_Algorithm = Get-Algorithm $Pool_Algorithm}
    $Pool_Algorithm_Norm = $Pool_Algorithms.$Pool_Algorithm
    $Pool_Coin = $PoolCoins_Request.$Pool_CoinSymbol.name
    $Pool_PoolFee = if ($Pool_Request.$Pool_Algorithm) {$Pool_Request.$Pool_Algorithm.fees} else {$Pool_Fee}
    $Pool_Currency = if ($PoolCoins_Request.$Pool_CoinSymbol.symbol) {$PoolCoins_Request.$Pool_CoinSymbol.symbol} else {$Pool_CoinSymbol}
    $Pool_User = $Wallets.$Pool_Currency

    if ($Pool_Algorithm_Norm -ne "Equihash" -and $Pool_Algorithm_Norm -like "Equihash*") {$Pool_Algorithm_All = @($Pool_Algorithm_Norm,"$Pool_Algorithm_Norm-$Pool_Currency")} else {$Pool_Algorithm_All = @($Pool_Algorithm_Norm)}
    
    $Pool_TSL = $PoolCoins_Request.$Pool_CoinSymbol.timesincelast

    if ($Pool_Request.$Pool_Algorithm.mbtc_mh_factor) {
        $Pool_Factor = [Double]$Pool_Request.$Pool_Algorithm.mbtc_mh_factor
    } else {
        $Pool_Factor = $(
            Switch ($Pool_Algorithm_Norm) {
                "Blake2s" {1000}
                "Sha256"  {1000}
                "Sha256t" {1000}
                "Keccak"  {1000}
                "KeccakC"  {1000}
                default   {1}
            })
    }

    if ($Pool_Factor -le 0) {
        Write-Log -Level Info "Unable to determine divisor for $Pool_Coin using $Pool_Algorithm_Norm algorithm"
        return
    }

    $Divisor = 1e9 * $Pool_Factor

    if (-not $InfoOnly) {
        $Stat = Set-Stat -Name "$($Name)_$($Pool_CoinSymbol)_Profit" -Value ([Double]$PoolCoins_Request.$Pool_CoinSymbol.estimate / $Divisor) -Duration $StatSpan -ChangeDetection $true -HashRate $PoolCoins_Request.$Pool_CoinSymbol.hashrate -BlockRate $PoolCoins_Request.$Pool_CoinSymbol."24h_blocks" -Quiet
    }

    foreach($Pool_Region in $Pool_Regions) {
        foreach($Pool_Currency in $Pool_Currencies) {
            foreach($Pool_Algorithm_Norm in $Pool_Algorithm_All) {
                [PSCustomObject]@{
                    Algorithm     = $Pool_Algorithm_Norm
                    CoinName      = $Pool_Coin
                    CoinSymbol    = $Pool_CoinSymbol
                    Currency      = $Pool_Currency
                    Price         = $Stat.$StatAverage #instead of .Live
                    StablePrice   = $Stat.Week
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+tcp"
                    Host          = "$Pool_Host"
                    Port          = $Pool_Port
                    User          = $Wallets.$Pool_Currency
                    Pass          = "{workername:$Worker},c=$Pool_Currency{diff:,d=`$difficulty}"
                    Region        = $Pool_RegionsTable.$Pool_Region
                    SSL           = $false
                    Updated       = $Stat.Updated
                    PoolFee       = $Pool_PoolFee
                    Workers       = $Pool_CoinsRequest.$Pool_CoinSymbol.workers
                    Hashrate      = $Stat.HashRate_Live
                    BLK           = $Stat.BlockRate_Average
                    TSL           = $Pool_TSL
                }
            }
        }
    }
}
