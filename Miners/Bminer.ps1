﻿using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [Bool]$InfoOnly
)

$Path = ".\Bin\Equihash-BMiner\bminer.exe"
$URI = "https://github.com/RainbowMiner/miner-binaries/releases/download/v10.7.0-bminer/bminer-lite-v10.7.0-31ee7bc-CUDA-9.2-amd64.zip"
$ManualURI = "https://bminer.me"
$Port = "307{0:d2}"
$DevFee = 2.0
$Cuda = "9.2"

if (-not $Session.DevicesByTypes.NVIDIA -and -not $InfoOnly) {return} # No NVIDIA present in system

$Commands = [PSCustomObject[]]@(
    [PSCustomObject]@{MainAlgorithm = "equihash"; SecondaryAlgorithm = ""; Params = ""; DevFee = 2.0} #" -nofee" #Equihash
    [PSCustomObject]@{MainAlgorithm = "equihash1445"; SecondaryAlgorithm = ""; Params = ""; DevFee = 2.0} #" -nofee" #Equihash 144,5
    #[PSCustomObject]@{MainAlgorithm = "ethash"; SecondaryAlgorithm = ""; Params = ""; DevFee = 0.65} #Ethash (ethminer is faster and no dev fee)
    [PSCustomObject]@{MainAlgorithm = "tensority"; SecondaryAlgorithm = ""; Params = ""; DevFee = 2.0} #" -nofee" #Bytom
    #[PSCustomObject]@{MainAlgorithm = "zhash"; SecondaryAlgorithm = ""; Params = ""; DevFee = 2.0} #" -nofee" #Zhash
    #[PSCustomObject]@{MainAlgorithm = "ethash"; SecondaryAlgorithm = "blake2s"; Params = ""; DevFee = 1.3} #Ethash + Blake2s
    #[PSCustomObject]@{MainAlgorithm = "ethash"; SecondaryAlgorithm = "blake14r"; Params = ""; DevFee = 1.3} #Ethash + Decred
)

$Coins = [PSCustomObject]@{
    default     = "--pers auto"
    AION        = "--pers AION0PoW"
    BTG         = "--pers BgoldPoW"
    BTCZ        = "--pers BitcoinZ"
    SAFE        = "--pers Safecoin"
    XSG         = "--pers sngemPoW"
    ZEL         = "--pers ZelProof"
    ZER         = "--pers ZERO_PoW"
}

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

if ($InfoOnly) {
    [PSCustomObject]@{
        Type      = @("NVIDIA")
        Name      = $Name
        Path      = $Path
        Port      = $Miner_Port
        Uri       = $Uri
        DevFee    = $DevFee
        ManualUri = $ManualUri
        Commands  = $Commands
		Coins     = @($Coins.PSObject.Properties.Name)
    }
    return
}

if (-not (Confirm-Cuda -ActualVersion $Session.Config.CUDAVersion -RequiredVersion $Cuda -Warning $Name)) {return}

$Session.DevicesByTypes.NVIDIA | Select-Object Vendor, Model -Unique | ForEach-Object {
    $Miner_Device = $Session.DevicesByTypes."$($_.Vendor)" | Where-Object Model -EQ $_.Model
    $Miner_Port = $Port -f ($Miner_Device | Select-Object -First 1 -ExpandProperty Index)
    $Miner_Port = Get-MinerPort -MinerName $Name -DeviceName @($Miner_Device.Name) -Port $Miner_Port
    $Miner_Model = $_.Model

    $DeviceIDsAll = $Miner_Device.Type_Vendor_Index -join ','

    $Commands | ForEach-Object {
        $MainAlgorithm = $_.MainAlgorithm
        $MainAlgorithm_Norm = Get-Algorithm $MainAlgorithm

        if (($Pools.$MainAlgorithm_Norm.Host -or $MainAlgorithm -eq "equihash1445") -and $Miner_Device) {

            $SecondAlgorithm = $_.SecondaryAlgorithm
            if ($SecondAlgorithm -ne '') {
                $SecondAlgorithm_Norm = Get-Algorithm $SecondAlgorithm
            }
            $Stratum = "$(if ($MainAlgorithm -eq "equihash") {"stratum"} else {$MainAlgorithm})$(if ($Pools.$MainAlgorithm_Norm.SSL) {"+ssl"})"

            if ($SecondAlgorithm -eq '') {
                $Miner_Name = (@($Name) + @($Miner_Device.Name | Sort-Object) | Select-Object) -join '-'
                $MinerCoin_Params = ""
                if ($MainAlgorithm_Norm -eq "Equihash24x5") {
                    if ($Pools.$MainAlgorithm_Norm.CoinSymbol) {$MinerCoin_Params = $Coins."$($Pools.$MainAlgorithm_Norm.CoinSymbol)"}
                    elseif ($Pools.$MainAlgorithm_Norm.CoinName) {$MinerCoin_Params = $Coins."$($Pools.$MainAlgorithm_Norm.CoinName)"}
                } elseif ($MainAlgorithm_Norm -eq "Equihash24x7") {
                    $MinerCoin_Params = $Coins.ZER
                }
                if ($MinerCoin_Params -eq "") {$MinerCoin_Params = $Coins.default}
                [PSCustomObject]@{
                    Name = $Miner_Name
                    DeviceName = $Miner_Device.Name
                    DeviceModel = $Miner_Model
                    Path = $Path
                    Arguments = "-devices $($DeviceIDsAll) -api 127.0.0.1:$($Miner_Port) -uri $($Stratum)://$(Get-UrlEncode $Pools.$MainAlgorithm_Norm.User):$(Get-UrlEncode $Pools.$MainAlgorithm_Norm.Pass)@$($Pools.$MainAlgorithm_Norm.Host):$($Pools.$MainAlgorithm_Norm.Port) $($MinerCoin_Params) -watchdog=false -no-runtime-info -gpucheck=0 $($_.Params)"
                    HashRates = [PSCustomObject]@{$MainAlgorithm_Norm = $Session.Stats."$($Miner_Name)_$($MainAlgorithm_Norm)_HashRate".Week}
                    API = "Bminer"
                    Port = $Miner_Port
                    Uri = $Uri
                    DevFee = $_.DevFee
                    ManualUri = $ManualUri
                }
            } else {
                $Miner_Name = (@($Name) + @($MainAlgorithm_Norm) + @($SecondAlgorithm_Norm) + @($Miner_Device.Name | Sort-Object) | Select-Object) -join '-'
                [PSCustomObject]@{
                    Name = $Miner_Name
                    DeviceName = $Miner_Device.Name
                    DeviceModel = $Miner_Model
                    Path = $Path
                    Arguments = "-devices $($DeviceIDsAll) -api 127.0.0.1:$($Miner_Port) -uri $($Stratum)://$(Get-UrlEncode $Pools.$MainAlgorithm_Norm.User):$(Get-UrlEncode $Pools.$MainAlgorithm_Norm.Pass)@$($Pools.$MainAlgorithm_Norm.Host):$($Pools.$MainAlgorithm_Norm.Port) -uri2 $($SecondAlgorithm)://$(Get-UrlEncode $Pools.$SecondAlgorithm_Norm.User):$(Get-UrlEncode $Pools.$SecondAlgorithm_Norm.Pass)@$($Pools.$SecondAlgorithm_Norm.Host):$($Pools.$SecondAlgorithm_Norm.Port) -watchdog=false -no-runtime-info -gpucheck=0 $($_.Params)"
                    HashRates = [PSCustomObject]@{
                        $MainAlgorithm_Norm = $($Session.Stats."$($MinerName)_$($MainAlgorithm_Norm)_HashRate".Week)
                        $SecondAlgorithm_Norm = $($Session.Stats."$($MinerName)_$($SecondAlgorithm_Norm)_HashRate".Week)
                    }
                    API = "Bminer"
                    Port = $Miner_Port
                    Uri = $Uri
                    DevFee = [PSCustomObject]@{
                        ($MainAlgorithm_Norm) = $_.DevFee
                        ($SecondAlgorithm_Norm) = 0
                    }
                    ManualUri = $ManualUri
                }
            }
        }
    }
}