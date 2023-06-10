function Remove-StringSpecialCharacter
{
<#
.SYNOPSIS
  This function will remove the special character from a string.
  
.DESCRIPTION
  This function will remove the special character from a string.
  I'm using Unicode Regular Expressions with the following categories
  \p{L} : any kind of letter from any language.
  \p{Nd} : a digit zero through nine in any script except ideographic 
  
  http://www.regular-expressions.info/unicode.html
  http://unicode.org/reports/tr18/

.PARAMETER String
  Specifies the String on which the special character will be removed

.SpecialCharacterToKeep
  Specifies the special character to keep in the output

.EXAMPLE
  PS C:\> Remove-StringSpecialCharacter -String "^&*@wow*(&(*&@"
  wow
.EXAMPLE
  PS C:\> Remove-StringSpecialCharacter -String "wow#@!`~)(\|?/}{-_=+*"
  
  wow
.EXAMPLE
  PS C:\> Remove-StringSpecialCharacter -String "wow#@!`~)(\|?/}{-_=+*" -SpecialCharacterToKeep "*","_","-"
  wow-_*

.NOTES
  Francois-Xavier Cat
  @lazywinadmin
  www.lazywinadmin.com
  github.com/lazywinadmin
#>
  [CmdletBinding()]
  param
  (
    [Parameter(ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [Alias('Text')]
    [System.String[]]$String,
    
    [Alias("Keep")]
    #[ValidateNotNullOrEmpty()]
    [String[]]$SpecialCharacterToKeep
  )
  PROCESS
  {
    IF ($PSBoundParameters["SpecialCharacterToKeep"])
    {
      $Regex = "[^\p{L}\p{Nd}"
      Foreach ($Character in $SpecialCharacterToKeep)
      {
        IF ($Character -eq "-"){
          $Regex +="-"
        } else {
          $Regex += [Regex]::Escape($Character)
        }
        #$Regex += "/$character"
      }
      
      $Regex += "]+"
    } #IF($PSBoundParameters["SpecialCharacterToKeep"])
    ELSE { $Regex = "[^\p{L}\p{Nd}]+" }
    
    FOREACH ($Str in $string)
    {
      Write-Verbose -Message "Original String: $Str"
      $Str -replace $regex, ""
    }
  } #PROCESS
}
Export-ModuleMember -Function Remove-StringSpecialCharacter

function Remove-StringDiacritic
{
<#
    .SYNOPSIS
        This function will remove the diacritics (accents) characters from a string.
        
    .DESCRIPTION
        This function will remove the diacritics (accents) characters from a string.
    
    .PARAMETER String
        Specifies the String on which the diacritics need to be removed
    
    .PARAMETER NormalizationForm
        Specifies the normalization form to use
        https://msdn.microsoft.com/en-us/library/system.text.normalizationform(v=vs.110).aspx
    
    .EXAMPLE
        PS C:\> Remove-StringDiacritic "L'�t� de Rapha�l"
        
        L'ete de Raphael
    
    .NOTES
        Francois-Xavier Cat
        @lazywinadmin
        www.lazywinadmin.com
#>
    
    param
    (
        [ValidateNotNullOrEmpty()]
        [Alias('Text')]
        [System.String]$String,
        [System.Text.NormalizationForm]$NormalizationForm = "FormD"
    )
    
    BEGIN
    {
        $Normalized = $String.Normalize($NormalizationForm)
        $NewString = New-Object -TypeName System.Text.StringBuilder
        
    }
    PROCESS
    {
        $normalized.ToCharArray() | ForEach-Object -Process {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($psitem) -ne [Globalization.UnicodeCategory]::NonSpacingMark)
            {
                [void]$NewString.Append($psitem)
            }
        }
    }
    END
    {
        Write-Output $($NewString -as [string])
    }
}
Export-ModuleMember -Function Remove-StringDiacritic