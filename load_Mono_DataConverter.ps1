# lobal Mono DataConverter

$compilerParameters = New-Object System.CodeDom.Compiler.CompilerParameters
$compilerParameters.CompilerOptions="/unsafe"
add-type -path .\DataConverter.cs -compilerparameters $compilerParameters
