# icread

Read ICobol XD files, and export to CSV

## background

My company has a lot of old icobol XD archives, still updated regularily, and we need to convert our XD files to CSV files.
This is a *quick and dirty* tool that does the job.

## how to use

icreader accepts 3 parameters:

    ./icreader.pl archive recordlayout recordsize
    
- archive is the .xd icobol file to be converted
- recordlayout is the .xdt file that describes the format of the icobol archive
- recordsize is the size of the record (I don't know how to calculate it, try with 8, 14, 20, etc.)

example:

    ./ireader.pl cobolArchive.xd recordLayout.xdt 24 > extractedData.csv

## record layout

icreader uses a standard xdt odbc file to describe the record layout (but please note that on the columns section the value must be empty):

    [Table]
    NumColumns=5
    MaxRecordSize=20
    
    [Columns]
    Year=
    Month=
    Description=
    Value=
    
    [Year]
    Type=UNSIGNED COMP
    Position=1
    Length=1
    Precision=2
    Scale=0
    
    [Month]
    Type=UNSIGNED COMP
    Position=2
    Length=1
    Precision=2
    Scale=0
    
    [Description]
    Type=ALPHANUMERIC
    Position=3
    Length=15
    
    [Value]
    Type=DISPLAY
    Position=17
    Length=3
    Precision=6

## author

Federico Thiella
http://stackoverflow.com/users/833073/fthiella

## notes

This software is not complete, it works perfectly on my files but it might not work on any icobol file. Please let me know if you need any improvement.
