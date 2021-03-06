param($username,$password,$domain,$url)
##
#
# vElemental.com
# Clinton Kitson @clintonskitson clintonskitson@gmail.com
# https://github.com/clintonskitson/Powershell-Adobe-AMF
#
#.\amf_call.ps1 
#
##



$HttpContentType = "application/x-amf"
[int]$global:responseUriCount = 1


$netAssembly = [Reflection.Assembly]::GetAssembly([System.Net.Configuration.SettingsSection])
IF($netAssembly) {
    $bindingFlags = [Reflection.BindingFlags] "Static,GetProperty,NonPublic"
    $settingsType = $netAssembly.GetType("System.Net.Configuration.SettingsSectionInternal")
    $instance = $settingsType.InvokeMember("Section", $bindingFlags, $null, $null, @())
    if($instance) {
        $bindingFlags = "NonPublic","Instance"
        $useUnsafeHeaderParsingField = $settingsType.GetField("useUnsafeHeaderParsing", $bindingFlags)
        if($useUnsafeHeaderParsingField) {
            $useUnsafeHeaderParsingField.SetValue($instance, $true) | out-null
        }
    }
}
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
[System.Net.ServicePointManager]::Expect100Continue = $false


[net.httpWebRequest] $req = [net.webRequest]::create($url)
$req.method = "POST"
$req.ContentType = $HttpContentType
$req.TimeOut = 5000
$req.Headers.Add("x-flash-version","10,3,181,34")
$req.Headers.Add("Accept-Encoding","gzip,deflate")$req.Headers.Add("Accept-Language: en-US")
$req.Accept = "*/*"


##
$webclient = New-Object System.Net.WebClient
$webclient.Headers.Add("Content-Type",$HttpContentType)
$webclient.Headers.Add("x-flash-version","10,3,181,34")
$webclient.Headers.Add("Accept-Encoding: gzip,deflate")
$Encode = new-object "System.Text.ASCIIEncoding"


function custom_httpWebRequest {
    param($cookie,$bytesRequest)
    [net.httpWebRequest] $req = [net.webRequest]::create($url)
    $req.method = "POST"
    $req.ContentType = $HttpContentType
    [array]$buffer = $bytesRequest
    $req.ContentLength = $buffer.length
    $req.TimeOut = 5000
    $req.Headers.Add("x-flash-version","10,3,181,34")
    $req.Headers.Add("Accept-Encoding","gzip,deflate")
    if($global:cookie) { 
        $req.Headers.Add("Cookie",$global:cookie)
    }
    $reqst = $req.getRequestStream()
    $reqst.write($buffer, 0, $buffer.count)
    $reqst.flush()
    $reqst.close()

    [net.httpWebResponse] $res = $req.getResponse()
    $resst = $res.getResponseStream()
    $ms = new-object system.io.memorystream
    $respBuffer = new-object byte[] (,4096)
    try { $bytesRead = $resst.read($respBuffer,0,$respBuffer.count)
        while ($bytesRead -gt 0) {
            $ms.Write($respBuffer,0,$bytesRead)
            $bytesRead = $resst.Read($respBuffer,0,$respBuffer.count)
        }
    } catch {}
    [array]$arrByteArray = $ms.toArray()
    $ms.flush()
    $ms.close()
    if($res.Headers["set-cookie"]) { $global:cookie = $res.Headers["set-cookie"] -split ";" | select -first 1 }
    return $arrByteArray
}

function updatePacket {
    param($templatePacket,$previousPacket)
    0..($templatePacket.messages.count-1) | %{ 
        $i=$_
        $templatePacket.messages[$i] | %{
            $templatePacket.messages[$i].responseUri = "/"+$global:responseUriCount++
            0..($tmpDeSer.messages[$i].data.count-1)  | %{
                $j=$_
                if($templatePacket.messages[$i].data[$j].messageId) {
                   $templatePacket.messages[$i].data[$j].messageId = [system.guid]::NewGuid().guid
                }
                if($templatePacket.messages[$i].data[$j].headers.DSid) {
                    $global:dsid = $previousPacket.messages[0].data | where {$_.DSid} | %{ $_.DSid }
                   if($global:dsid) {  $templatePacket.messages[$i].data[$j].headers.DSid = $global:dsid }
                } 
            }
        }
    }
    return $templatePacket
}

function serializePacket {
    param($packet)
    $tmpSer = .\amf_serialize.ps1 -amfPacket $packet
    [array]$arrBytesPacket = $tmpSer -split "" | %{ try {[byte][char]$_} catch { } }
    return $arrBytesPacket
}

function preparePacket {
    param ($templateXml,$previousPacket)
    [psobject]$packet = import-CliXml $templateXml
    $packet = updatePacket -templatePacket $packet -previousPacket $previousPacket
    return $packet
}

## CALL 1
$webclient.DownloadString($url) | out-null
if($cookie = ($webclient.ResponseHeaders.get("set-cookie") -split ";" | select -first 1)) {
    $webclient.Headers.Add("Cookie",$cookie) | out-null
}
$req.Headers.Add("Cookie",$webclient.Headers.get("Cookie"))

## CALL 2
[psobject]$packet = import-CliXml "login.psobject.xml"
$packet.messages[0].responseUri = "/"+$global:responseUriCount++
$packet.messages[0].data[0].messageId = [system.guid]::NewGuid().guid
[array]$arrRespBytes = custom_httpwebrequest -bytesrequest (serializePacket -packet $packet) -cookie $global:cookie
$tmpDeSer = .\amf_deserialize.ps1 -arrByteResponse $arrRespBytes

## CALL 3
$packet = preparePacket -templateXml "secureamf.call.psobject.xml" -previousPacket $tmpDeser
[array]$arrRespBytes = custom_httpwebrequest -bytesrequest (serializePacket -packet $packet) -cookie $global:cookie
$tmpDeser = .\amf_deserialize.ps1 -arrByteResponse $arrRespBytes 

### CALL 5
$packet = preparePacket -templateXml "up_login.psobject.xml" -previousPacket $tmpDeser
[array]$packet.messages[0].data[0].body = new-object 'object[]' 0
[array]$packet.messages[0].data[0].body = @($username,$password,$domain)
[array]$arrRespBytes = custom_httpwebrequest -bytesrequest (serializePacket -packet $packet) -cookie $global:cookie
$tmpDeser = .\amf_deserialize.ps1 -arrByteResponse $arrRespBytes 

### CALL 6 - do a ping
$packet = preparePacket -templateXml "ping.psobject.xml" -previousPacket $tmpDeser
[array]$arrRespBytes = custom_httpwebrequest -bytesrequest (serializePacket -packet $packet) -cookie $global:cookie
$tmpDeser = .\amf_deserialize.ps1 -arrByteResponse $arrRespBytes 
#$a.messages[0].data[1] = success (_explicitType -eq success) ?


