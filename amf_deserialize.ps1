param ([byte[]]$arrByteResponse,[string]$encodedResponse)
##
#
# vElemental.com
# Clinton Kitson @clintonskitson clintonskitson@gmail.com
# https://github.com/clintonskitson/Powershell-Adobe-AMF
#
#.\amf_deserialize.ps1 
#
##


. .\load_mono_DataConverter.ps1
. .\load_shift.ps1

##note on encodedresponse-- should be receiving as bytestream for best results
if($encodedResponse) { 
    $arrByteResponse = %{
        $encodedResponse -split "" | %{ try { [byte][char]$_ } catch {} }
    }
}

$global:deserializedPacket = new-object -type psobject -property @{headers=$null;messages=$null;headerTable=$null;amfVersion=$null;}

 
function readData {
     $type = ($objBytes.arr[$objBytes.pos++].toString("X2"))
      #write-host "readData: $type"
      switch ([string]$type) {      
           #amf3 is now most common, so start with that
            "11" { #Amf3-specific
                return readAmf3Data
                break; 
                }
            "00" { #number
                readDouble }
            "01" { #boolean
                return $objBytes.arr[$objBytes.pos++] -eq 1 }
            "02" { #string
                throw readUTF }
            "03" { #object Object
                return readAmf3Data }
            "04" { 
                return }
            "05" { #ignore movie clip
                throw "null"; }
            "06" { #undefined
                throw "new Amfphp_Core_Amf_Types_Undefined()" }
            "07" { #Circular references are returned here
                throw "readReference()" }
            "08" { #mixed array with numeric and string keys
                throw "readMixedArray()" }
            "09" { #object end. not worth , TODO maybe some integrity checking
                throw "null" }
            "0A" { #array
                return readArray }
            "0B" { #date
                throw "readDate()" }
            "0C" { #string, strlen(string) > 2^16
                throw "readLongUTF()" }
            "0D" { #mainly internal AS objects
                throw "null" }
            "0F" { #XML #ignore recordset
                throw "readXml()" }
            "10" { #Custom Class
                throw "readCustomClass()" }
            default { #unknown case
                #throw "unknown"
                throw "new Amfphp_Core_Exception('Found unhandled type with code: $type')"
                #exit();
                #break; 
                }
        }
        return $data;
} 

function readAmf3Data {
    #AMF3 data found, so mark it in the deserialized packet. This is useful to know what kind of AMF to send back
    #$this->deserializedPacket->amfVersion = Amfphp_Core_Amf_Constants::AMF3_ENCODING;
    
    $tmpByte = $objBytes.arr[$objBytes.pos++]
    #write-host "readAmf3Data: pre-type byte: $tmpByte"
    $type = ($tmpByte.toString("X2"))
    #write-host "readAmf3Data: $type"
    switch ([string]$type) {
        "00" {
            throw "new Amfphp_Core_Amf_Types_Undefined();" }
        "01" { #null
            #write-host "readAmf3Data: null"
            return $null; }
        "02" { #boolean false
            #write-host "readAmf3Data: false"
            return $false;  }
        "03" { #boolean true
            #write-host "readAmf3Data: true"
            return $true;  }
        "04" {
            return readAmf3Int }
        "05" {
            return readDouble }
        "06" {
            return readAmf3String }
        "07" { 
            throw "readAmf3XmlDocument()" }
        "08" { 
            throw "readAmf3Date()" }
        "09" { 
            return readAmf3Array }
        "0A" { 
            return readAmf3Object }
        "0B" { 
            throw "readAmf3Xml()" }
        "0C" { 
            throw "readAmf3ByteArray()" }
        default {
            throw "new Amfphp_Core_Exception undefined Amf3 type encountered: $type)" 
        }
    }
}

function readAMf3Int {
    [int]$result = 0
    $b = $objBytes.arr[$objBytes.pos++]
    #write-host "readAMF3Int:: b:$b"
    if($b -lt 128) { return $b }
    $result = [shift]::left(($b -band 0x7F),7)
    $b = $objBytes.arr[$objBytes.pos++]
    #write-host "readAMF3Int:: b:$b result:$result"
    if($b -lt 128) { return ($result -bor $b) }
    $result = [shift]::left(($result -bor ($b -band 0x7F)),7)
    $b = $objBytes.arr[$objBytes.pos++]
    #write-host "readAMF3Int:: b:$b result:$result"
    if($b -lt 128) { return ($result -bor $b) }
    $result = [shift]::left(($result -bor ($b -band 0x7F)),8)
    $b = $objBytes.arr[$objBytes.pos++]
    #write-host "readAMF3Int:: result:$result -bor b:$b"
    return ($result -bor $b)    
}

function readBuffer {
    param ($strLen)
        #write-host "readBuffer:strLen $strLen"
        $data = "";
        $data = (($objBytes.arr[($objBytes.pos)..($objBytes.pos+$strLen-1)]) | %{ [system.text.encoding]::utf8.getstring($_) }) -join ""
        $objBytes.pos += $strLen;
        return $data;
}

        
function readAmf3String {
    $strref = readAmf3Int;
    #write-host "readAmf3String::strref: $strref"
    if (($strref -band "0x01") -eq 0) {
        $strref = [shift]::right($strref,1);
        if ($strref -ge $global:storedStrings.count) {
            throw "new Amfphp_Core_Exception('Undefined string reference: ' . $strref, E_USER_ERROR);"
            return $false;
        }
        return [string]$global:storedStrings[$strref];
    } else {
        $strlen = [shift]::right($strref,1);
        $str = "";
        if ($strlen -gt 0) {
            $str = readBuffer -strLen $strLen;
            #write-host "readAmf3String:storing $str";
            [array]$global:storedStrings += $str;
        }
       # #write-host "string: $str"
       return [string]$str;
    }
}

function readAmf3Object {
    $handle = readAmf3Int
    #write-host "readAmf3Object::handle1: $handle"
    $inline = (($handle -band 1) -ne 0);
    $handle = [shift]::right($handle,1);
    #write-host "readAmf3Object::handle2: $handle"
    $tmpOrder = @()
    
    if($inline) {
        $inlineClassDef = (($handle -band 1) -ne 0)
        $handle = [shift]::right($handle,1)
        #write-host "readAmf3Object::handle3: $handle"
        
        if($inlineClassDef) {
            $typeIdentifier = readAmf3String
            $typedObject = $typeIdentifier -and ($typeIdentifier -ne "" -and $typeIdentifier -ne $null)
            #flags that identify the way the object is serialized/deserialized
            $externalizable = (($handle -band 1) -ne 0);
            $handle = [shift]::right($handle,1);
            #write-host "readAmf3Object::handle4: $handle"
            $dynamic = (($handle -band 1) -ne 0);
            $handle = [shift]::right($handle,1);
            #write-host "readAmf3Object::handle5: $handle"
            
            [int]$classMemberCount = $handle; 
            #write-host "inline::classMemberCount $classMemberCount"
            $classMemberDefinitions = @();
            for ($k = 0; $k -lt $classMemberCount; $k++) {
                [array]$classMemberDefinitions += readAmf3String
            }            

            $classDefinition = @{ "type"=$typeIdentifier;"members"=$classMemberDefinitions;
                "externalizable"=$externalizable;"dynamic"=$dynamic }
            [array]$global:storedDefinitions += $classDefinition;

        } else {
            #a reference to a previously passed class-def
            $classDefinition = $global:storedDefinitions[$handle];
        }
    } else {
        #an object reference
        #write-host "readAmf3Object::reference::obj ref:$($global:storedObjects[$handle])"
        return $global:storedObjects[$handle];
    }

    $type = $classDefinition['type'];
    $obj = new-object -type psobject   

    [array]$members = $classDefinition['members'];
    [int]$memberCount = $members.count
    #write-host "memberCount: $memberCount" -fore red
      
    for($j = 0; $j -lt $memberCount; $j++) {
        #write-host "readAmf3Object:writeMember $($members[$j])"
        $key = $members[$j]
        $val = readAmf3Data
        ##write-host "readAmf3Object::dynamic::obj name:$key value:$value type: $($val.gettype())"
        $obj | add-member -type noteproperty -name $key -value $val
        ##write-host "readAmf3Object::dynamic::obj after add-member type:$(($obj.$key).gettype())"
        $tmpOrder += $key
    } 
    
    #embedded array?
    if($objBytes.arr[$objBytes.pos] -eq 9) {
        readAmf3Data
    }
    
    if ($classDefinition['dynamic']) {
        $key = readAmf3String
        while ($key -ne "") {
            $value = readAmf3Data
            #write-host "readAmf3Object::dynamic::obj name:$key value:$value type: $($value.gettype())"
            $obj | add-member -type noteproperty -name $key -value $value
            #write-host "readAmf3Object::dynamic::obj after add-member type:$($obj.$key)"
            $tmpOrder += $key
            $key = readAmf3String
        }
    }        

    if ($type -ne '') {
        $explicitTypeField = "_explicitType"
        #write-host "readAmf3Object::explicit::obj name:$explicitTypeField value:$type"
        $obj | add-member -type noteproperty -name $explicitTypeField -value $type
        #$tmpOrder = $explicitTypeField
    }

    #add order if it doesn't exist to keep order due to powershell not remembering instantiation order
    if(!$obj."_order") {
        $obj | add-member -type noteproperty -name _order -value @($tmpOrder)
    } else {
        [array]$obj."_order" += @($tmpOrder)
    }

    [array]$global:storedObjects += $obj
    return $obj
}

function readInt {
     return ([shift]::left([int]$objBytes.arr[$objBytes.pos++],8) -bor [int]$objBytes.arr[$objBytes.pos++])
}

function readUTF {
    $length = readInt
    #write-host "readUTF::length: $length"
    if($length -eq 0 -or $objBytes.pos+$length -ge $objBytes.arr.count) { return "" } else {
        $val = ($objBytes.arr[($objBytes.pos)..($objBytes.pos+$length-1)] | %{ [char][byte]$_ }) -join ""
        $objBytes.pos += $length
        return $val
    } 
}

function readArray {
    #write-host "readArray"
    $ret = @()
    $amf0storedObjects = @()
    $length = readLong
    #write-host "readArray::readLong: $length"
    for ($l = 0; $l -lt $length; $l++) {
        [array]$ret += readData
    }
    [array]$global:amf0storedObjects += $ret
    return $ret
}  

function readLong {
    #write-host "readLong"
    return (
        [shift]::left([int]$objBytes.arr[$objBytes.pos++],24) -bor 
        [shift]::left([int]$objBytes.arr[$objBytes.pos++],16) -bor
        [shift]::left([int]$objBytes.arr[$objBytes.pos++],8) -bor
        [int]$objBytes.arr[$objBytes.pos++]
        )
}

function readDouble {
    $length = 8
    $val = ""
    $val = [mono.dataconverter]::unpack("dflt",($objBytes.arr[($objBytes.pos+$length-1)..($objBytes.pos)]),0)
    #write-host "readDouble::val: $val" -fore "green"
    $objBytes.pos += $length
    return $val
}
 
function readAmf3Array {
    #write-host "readAmf3Array"
    $handle = readAmf3Int;
    $inline = (($handle -band 1) -ne 0);
    $handle = [shift]::right($handle,1);
    #write-host "readAmf3Array inline:$inline handle:$handle"
    if ($inline) {
        $hashtable = @{};
        #$this->storedObjects[] = & $hashtable;
        $key = readAmf3String;
        while ($key -ne "") {
            #write-host "readAmf3Array:key $key"
            $value = readAmf3Data;
            $hashtable[$key] = $value;
            $key = readAmf3String;
        }
        
        for ($m = 0; $m -lt $handle; $m++) {
            #write-host "readAmf3Array:looping through handles"
            #Grab the type for each element.
            $value = readAmf3Data;
            if($value -eq "en_US") {
                #throw
                $tmpArr = new-object 'object[,]' 0,2
                $tmpArr += ,@($value)
                remove-variable value
                $value = $tmpArr
            }
            [array]$hashtable[[int]$m] = $value;
        }
        #write-host "returning hashtable with keys $($hashtable.keys)"
        try { [psobject]$tmpObj = new-object -type psobject -property $hashtable } catch { [psobject]$tmpObj = new-object -type psobject }
        [array]$arrBoolResults = $tmpObj.psobject.properties | %{ [int32]::tryparse($_.name,[ref]$null) }
        if($false -notcontains $arrBoolResults) {
            $tmpObj2 = $tmpObj
            $tmpObj = new-object 'object[,]' 0,2
            $tmpObj += ,@($tmpObj2.psobject.properties | sort name | %{ $_.value })
        }
        if(!$tmpObj -and $tmpObj -ne $false) { 
            $tmpObj = new-object 'object[,]' 0,2
            $tmpObj += ,@("")
            #write-host "readAmf3Array:tmpobj blank array, so now $(try {$tmpObj.gettype().basetype.name} catch {})" -fore black 
        }
        if($tmpObj.gettype().basetype.name -match "Array") { return ,($tmpObj) } else { return $tmpObj }
    } else {
        return $global:storedObjects[$handle];
    }
}   

$objBytes = new-object -type psobject -property @{ arr = $arrByteResponse; count = $arrByteResponse.count ; pos = 0 }

## read headers 
$global:topByte = $objBytes.arr[$objBytes.pos++]
$global:secondByte = $objBytes.arr[$objBytes.pos++]
if(@(0,3) -notcontains $secondByte) { throw "invalid AMFpacket detected, first byte is not 0 or 3";break }
$headersLeftToProcess = readInt
#write-host "headersLeftToProcess: $headersLeftToProcess"
for ($i = 0; $i -lt $headersLeftToProcess; $i++) {
    $name = readUTF
    $required = ($objBytes.arr[$objBytes.pos++]) -eq 1
    $objBytes.pos += 4
    [array]$content = readData
    $header = new-object -type psobject -property @{name=$name;required=$required;content=$content}
    [array]$global:deserializedPacket.headers += $header
}

## read messages
$messagesLeftToProcess = readInt
#write-host "messagesLeftToProcess: $messagesLeftToProcess"
for ($i = 0; $i -lt $messagesLeftToProcess; $i++) {
    $global:storedStrings = @()
    $global:storedObjects = @()
    $global:storedDefinitions = @()
    $global:amf0storedObjects = @()
    $data = @()
    $target = readUTF
    $response = readUTF
    $first = ""
    #write-host $($objBytes.arr[($objBytes.pos+7)..($objBytes.pos-3)] -join " ") -back red 
    #write-host $($objBytes.arr[($objBytes.pos+3)..$objBytes.pos]  -join " ") -back red
    $length = readLong $objBytes.arr[($objBytes.pos+3)..$objBytes.pos]
    #write-host "Message object length is $length"
    $targetBreak = $($length+$objBytes.pos-1)
    #write-host "Target character break point is $targetBreak"
    #write-host "Data loop check is $targetBreak -gt $($objBytes.pos) or object length $length is less than 0" -back green
    $first = $true
    while ($targetBreak -gt $objBytes.pos -or $length -lt 0) {
        #write-host "Data loop iterate is $targetBreak -gt $($objBytes.pos) or object $length is less than 0" -back green
        [array]$data += readData
        $length = readLong 
        $first=$false
        if($length -gt 0) { 0 | %{ $objBytes.pos-- | out-null } }
        0..2 | %{ $objBytes.pos-- | out-null } 
    }
    #write-host "Data loop end because $targetBreak is not -gt $($objBytes.pos) or object length is $length" -back green
    $message = new-object -type psobject -property @{targetUri=$target;responseUri=$response;data=$data}
    [array]$global:deserializedPacket.messages += $message
}



$global:deserializedPacket.amfVersion = $global:secondByte
$global:deserializedPacket