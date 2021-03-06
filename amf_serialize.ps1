param ([psobject]$amfPacket)

##
#
# vElemental.com
# Clinton Kitson @clintonskitson clintonskitson@gmail.com
# https://github.com/clintonskitson/Powershell-Adobe-AMF
#
#.\amf_serialize.ps1 
#
##

if(!$amfPacket) { throw "no AMF packed passed" }
. .\load_mono_DataConverter.ps1 | out-null
. .\load_shift.ps1 | out-null

[string]$global:outBuffer = ""

function resetReferences {
    #write-host "resetReferences" -fore red
    $global:amf0storedObjects = @()
    $global:storedStrings = @()
    $global:storedObjects = @()
    $global:className2TraitsInfo = @{}
}


function serialize {
    writeByte 0
    #write-host "amfVersion:$($global:packet.amfVersion)"
    writeByte($global:packet.amfVersion)
    [array]$arrHeaders = $global:packet.headers 
    $count = $arrHeaders.count
    writeInt $count
    for ($i = 0; $i -lt $count; $i++) {
        resetReferences
        [array]$header = $arrHeaders[$i] | %{ $tmpPacket=$_;$_.psobject.properties | select name,@{n="data";e={$_.value}},@{n="required";e={$tmpPacket.required}} }
        [array]::reverse($header)
        if($header) { 
            $header | %{ 
                writeUTF $_.name
                if($_.required) {
                    writeByte 1
                } else {
                    writeByte 0
                }
                [string]$tempBuf = $global:outBuffer
                $global:outBuffer = ""
                writeData $_.data
                [string]$serializedHeader = $global:outBuffer
                [string]$global:outBuffer = $tempBuf
                writeLong $serializedHeader.length
                [string]$global:outBuffer += $serializedHeader
            }
        }
    } 
    $count = $global:packet.messages.count
    [array]$arrMessages = $global:packet.messages
    writeInt $count
    for ($i = 0; $i -lt $count; $i++) {
        resetReferences
        $message = $arrMessages[$i]
        $currentMessage = $message #ref
        writeUTF $message.targetUri
        writeUTF $message.responseUri        
        [string]$tempBuf = $global:outBuffer
        $global:outBuffer = ""
        if($message.data.count -eq 1) { writeByte 10 }
        $first = $true              
        0..($message.data.count-1) | %{
                if($first) { 
                    $first=$false
                    if($message.data.count -gt 1) { writeLong -1 } else { writeLong 1 } 
                }
                writeData $message.data[$_]
                #writeByte 1 
        }
        [string]$serializedMessage = $global:outBuffer
        [string]$global:outBuffer = $tempBuf
        if($message.data.count -eq 1) { writeLong $serializedMessage.length }
        [string]$global:outBuffer += $serializedMessage
    }

    return $global:outBuffer
}

function writeData {
    param ($d)
    #write-host "writeData:d $d"
    if($global:packet.amfVersion -eq 3) {
        writeByte "0x11"
        writeAmf3Data $d  
        return
    }else {
        throw "writeData had unexpected d, not amf3?: $d"
    }
}

function writeUTF {
    param($s)
    #write-host "writeUTF:s $s"
    if($s) { 
        writeInt ($s.length)
        $global:outBuffer += $s
    }else { writeInt 0 }
}

function writeInt {
    param($byte)
    #write-host "writeInt:byte $byte"
    $b = [bitconverter]::getbytes([int]$byte) | select -first 2
    [array]::reverse($b)
    $b | %{ writeByte $_ }
}

function writeByte {
    param($byte)
    #write-host "writeByte:byte $byte"
    $global:outBuffer += [char][byte]$byte
}

function writeDouble {
    param($byte)
    #write-host "writeDouble"
    $b = [mono.DataConverter]::pack("d",[byte]"$byte",0)
    [array]::reverse($b)
    $b | %{ writeByte $_ }
}

function writeAmf3String {
    param($d)
    #write-host "writeAMf3String:d $d $($d.gettype())" -fore black
    if($d -eq "") {
        writeByte 1
        return
    } 
    if(!(handleReference $d $global:storedStrings)){
        writeAmf3Int (([shift]::left($d.length,1) -bor 1))
        $global:outBuffer += $d
    }
}

function writeAmf3Int {
    param($d)
    #write-host "writeAMf3Int:d $d"
    getAmf3Int ($d)
}

function getAmf3Int {
    param($d)
    #write-host "getAmf3Int:d $d"
    $tmpReturn = %{ 
     #   if($d -lt 0 -or $d -ge 0x200000) {
    #        (([shift]::right($d,22) -band 0x7f) -bor 0x80)
   #         (([shift]::right($d,15) -band 0x7f) -bor 0x80)
  #          (([shift]::right($d,8) -band 0x7f) -bor 0x80)
 #           ($d -band 0xFF)
#
#         } else {

       #     if($d -ge 0x4000) {
      #          (([shift]::right($d,14) -band 0x7F) -bor 0x80)
     #       }
    #        if($d -ge 0x80) {
   #             (([shift]::right($d,7) -band 0x7f) -bor 0x80)
  #          }
 #           $d -band 0x7F
#        }
        $d = $d -band 0x1fffffff
        if($d -lt 0x80) {
            $d
        } elseif ($d -lt 0x4000) {
            ([shift]::right($d,7) -band 0x7f) -bor 0x80
            $d -band 0x7f
        } elseif ($d -lt 0x200000) {
            ([shift]::right($d,14) -band 0x7f) -bor 0x80
            ([shift]::right($d,7) -band 0x7f) -bor 0x80
            $d -band 0x7f
        } else {
            ([shift]::right($d,22) -band 0x7f) -bor 0x80
            ([shift]::right($d,15) -band 0x7f) -bor 0x80
            ([shift]::right($d,8) -band 0x7f) -bor 0x80
            $d -band 0xff
        }
    }
    #write-host "getAMf3Int: $d return $tmpReturn"
    $tmpReturn | %{ writeByte $_ }
}

function writeAmf3Bool {
    param($d)
    #write-host "writeAmf3Bool"
    if($d) { writeByte 3 } else { writeByte 2 }
}

function writeAmf3Null {
    #write-host "writeAmf3Null"
    writeByte 1
}

function writeLong {
    param ($l)
    #write-host "writeLong::l $l"
    $b = [bitconverter]::getbytes([long]$l) | select -first 4
    [array]::reverse($b)
    $b | %{ writeByte $_ }
}

function writeAmf3Data {
    param($d)
    #write-host "writeAmf3Data:d $d"
    if(!$d -and $d -ne 0 -and $d -ne $false -and $d -ne "") {
        writeAmf3Null
        return
    }
    elseif($d.gettype().name -eq "byte") {
        writeByte 4
        writeAmf3Int $d
        return
    }
    elseif($d.gettype().name -eq "Int32") { 
        writeAmf3Number $d
        return
    }elseif($d.gettype().name -match "single|double") {
        writeByte 1
        writeDouble $d
        return
    }elseif($d.gettype().name -eq "String") {
        writeByte 6
        writeAMf3String $d $
        return
    }elseif($d.gettype().name -eq "Boolean") {
        writeAmf3Bool $d
        return
    }elseif($d.gettype().basetype.name -eq "Array" -or $d.gettype().tostring() -eq "System.Collections.ArrayList") {
        writeArrayOrObject $d
        return
    }elseif($d.gettype().name -eq "PSCustomObject" -or $d.tostring() -eq "System.Collections.Hashtable") {
        if($d.tostring() -eq "System.Collections.Hashtable") { $d = new-object -type psobject -property $d }
        writeAmf3Object $d
        return        
    }else { 
        throw "writeAmf3Data didn't match supported type: $d $($d.gettype())"
    }
}

function writeAmf3Number {
    param($d)
    #write-host "writeAmf3Number:d $d"
    if($d -ge -268435456 -and $d -le 268435455) {
        writeByte 4
        writeAmf3Int $d
    } else {
        writeByte 5
        writeDouble $d
    }
}

function writeAmf3Object {
    param($d)
    #write-host "writeAmf3Object:d $d"
    #ensure there is more to the object than just a blank "_order" property
    if($d.psobject.properties | group name | where {$_.name -ne "_order"}){
        writeByte 10
        if(handleReference $d $global:storedObjects) {
            writeByte 1 
            return
        }
        $explicitTypeField = "_explicitType" 
        if($d.$explicitTypeField) { 
            #write-host "writeAmf3Object:explicit $d" -fore red
            $className = $d.$explicitTypeField
            $propertyNames = $null
            
            if($global:className2TraitsInfo[$classname]) {
                $traitsInfo = $global:className2TraitsInfo[$className]
                $propertyNames = $traitsInfo["propertyNames"]
                $referenceId = $traitsInfo["referenceId"]
                $traitsReference = [shift]::left($referenceId,2) -bor 1
                #writeAmf3Int $traitsReference ??????
                
            }else {
                
                $propertyNames = @()
                #write-host "writeAmf3Object:add_propNames"
                if($d."_order") {
                    $d."_order" | %{ 
                        if($_ -ne $explicitTypeField) {
                            #write-host "amf3Object:add_propNames_ordered $_"
                            [array]$propertyNames += $_
                        }
                    }
                } else {
                    $d.psobject.properties | sort name | where {$_.name -ne "_order"} | %{
                        if($_.name -ne $explicitTypeField) {        
                            #write-host "amf3Object:add_propNames_noorder $_.name"
                            [array]$propertyNames += $_.name
                        }
                     }
                }
                          
                $numProperties = $propertyNames.count
                $traits = [shift]::left($numProperties,4) -bor 3   
                writeAmf3Int $traits
                writeAmf3String $className
                $propertyNames | %{ writeAmf3String $_ }
                $traitsInfo = new-object -type psobject -property @{referenceId = $global:className2TraitsInfo.count;propertyNames=$propertyNames}
                $global:className2TraitsInfo[$className] = $traitsInfo
            }
            
            if($propertyNames) { 
                $propertyNames | %{
                    #write-host "writeAmf3Object:from propertNames array, write name:$_ value:$($d.$_)"
                    writeAmf3Data $d.$_
                }
            }       
            
        } elseif($d -and ($d.psobject.properties | group name | where {$_.name -ne "_order"})) {
            #write-host "writeAmf3Object:noexplicit $d" -fore green
            writeAmf3Int "0xB"
            writeAmf3String "" 
            if($d."_order") {
                $d."_order" | %{ 
                    #write-host "writeAmf3Object:noexplicit:_order setting $_ to $($d.$_)" -fore red
                    if($_ -ne $explicitTypeField -and $_ -ne "_order") {
                        writeAmf3String $_ 
                        writeAmf3Data $d.$_
                    }
                }
            } else {
                $d.psobject.properties | sort name | where {$_.name -ne "_order"} | %{
                    #write-host "writeAmf3Object:noexplicit:noorder setting $d to $($d.$_)" -fore red
                    if($d.name -ne $explicitTypeField -and $_.name -ne "_order") {        
                        writeAmf3String $_.name; 
                        writeAmf3Data $_.value 
                    }
                }      
            } 
            writeByte 1         
        }
  #
    }elseif($d.psobject.properties | group name | where {$_.name -eq "_order"}) {
        writeByte 10
        writeByte 5
        writeByte 1
    }else {
        writeByte 10
        writeByte 1
    }
    
}


function writeArrayOrObject {
    param($d)
    #write-host "writeArrayOrObject:d $d"
    if(handleReference $d $global:amf0StoredObjects) {
        return
    }
    
    $numeric = @()
    $string = @()
    $len = $d.count
    $largestKey = -1
    
    $tmpObj = new-object -type psobject
    if($d.gettype().basetype.name -eq "Array" -or $d.gettype().tostring() -eq "System.Collections.ArrayList") {
        if($d.count -gt 0) { 0..($d.count-1) | %{ $tmpObj | add-Member -type noteproperty -name $_ -value $d[$_] } }
    } else {
        $d.psobject.properties | %{ $tmpObj | add-Member -type noteproperty -name $_.name -value $_.value }
    }
    [array]$arrBoolNum = $tmpObj.psobject.properties | %{ try {[int]::TryParse($_.name,[ref]$null)} catch {} }
    $num_count = $arrBoolNum | group | where {$_.name -eq $true} | %{ $_.count }
    $str_count = $arrBoolNum | group | where {$_.name -eq $false} | %{ $_.count }
    
    if(($num_count -gt 0 -and $str_count -gt 0) -or ($num_count -gt 0 -and $largestKey -ne ($num_count - 1))) {
        #writeByte 8
        #writeLong $num_count
        WriteByte 9
        writeObjectFromArray $tmpObj
    }elseif($num_count -gt 0){
        #wrong part?
        writeByte 10
        writeLong $num_count
        $d | %{ writeData $_ }
    }elseif($str_count -gt 0){
        writeByte 9
        writeObjectFromArray $tmpObj
    }else {
        writeByte 10
        writeInt 0
        writeInt 0
    }
}

function writeObjectFromArray {
    param($d)
    #write-host "writeObjectFromArray:d $d"
    $count = ($d.psobject.properties | where {$_.name -notmatch "_order"} | measure | %{$_.count}) #where {$_.TypeNameOfValue -notmatch "System.Object"} 
    if($count -eq 1 -and !($d.psobject.properties | %{ $_.value } | where {$_}) -and ($d.psobject.properties | %{ $_.value }) -ne $false) { 
        writeByte 1
        writeByte 1
    } else {
        writeByte ([shift]::left($count,1) -bor 1)
        $count = ($d.psobject.properties | where {$_.name -notmatch "_order"} | where {$_.TypeNameOfValue -notmatch "System.Object"} | measure | %{$_.count}) #
        writeByte 1
        $d.psobject.properties | sort name | %{ writeAMf3Data $_.value }
    }
    
}

function writeObjectEnd {
    #write-host "writeObjectEnd"
    writeInt 0
    writeByte 9
}

function writeTypedObject {
    param($d)
    #write-host "writeTypedObject:d $d"
    if(handleReference $d $global:Amf0StoredObjects) {
        return
    }
    writeByte 16
    $explicitTypeField = "_explicitType"
    $className = $d.$explicitTypeField
    if(!$className) {
        throw "no explicit type field passed to writeTypedObject"
    }
    remove-variable explicitTypeField | out-null
    writeUTF $className
    $d.psobject.properties | %{ 
        #what is \0? for
        if($_.value) {
            writeUTF $_.name
            writeData $_.value
        }
    } 
    writeObjectEnd
}

function writeAnonymousObject {
    param($d)
    #write-host "writeAnonymousObject:d $d"
    if(!(handleReference $d $global:amf0StoredObjects)) {
        writeByte 3
        $d.psobject.properties | %{ 
            #\0??
            if($_.value) {
                writeUTF $_.name
                writeData $_.value 
            }
        } 
        writeObjectEnd
    }
}

function handleReference {
    param ($obj,$references)
    #write-host "handleReference: obj:$obj references:$references"
    $key = $false
    $references | %{ if([object]::referenceequals($obj,$_)) { $key = $obj;break } } #??
    if(!$key -and $references.count -ge 1024) {
        #need work   
    }
    if($key -ne $false) {
        if($global:packet.amfVersion -eq 0) {
            writeReference $key
        } else {
            #write-host "handleReference: shiftling and setting handle"
            $handle = [shift]::left($key,1)
            writeAmf3Int $handle
        }
        return $true
    }else {
        return $false
    }
}

function writeReference {
    param($num)
    #write-host "writeReferene:num $num"
    writeByte 7
    writeInt $num
}

$global:packet = $amfPacket
resetReferences
serialize

