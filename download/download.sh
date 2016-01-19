#!/bin/bash

#######################################################################
# When answering 'Y' to all questions during the script,              #
# your directory will look like this:                                 #
#                                                                     #
# download.sh - this script                                           #
# polygon - plain polygon coordinates                             #
# output/request_log.txt - all requests you sent                      #
# output/preview/${polygon}/preview_${UUID} for each file - a preview image      #
# output/${S2A} for each file - a metadata file                       #
#######################################################################



#######################################################################
# Declaring User variables...                                         #
#######################################################################

user=""
password=""

# ask for credentials - outcomment if you declare above
echo "Please enter Username for ESAs Scihub: "
read user
echo "Please enter Password: "
read password

#coordinates need to be in EPSG:4326 like "x1 y1, x2 y2, x3 y3, ..., x1 y1"
polygonfile="mongolia"

#######################################################################
# Declaring variables which User don't need to touch...               #
#######################################################################
baseUri="https://scihub.esa.int/apihub"
wget="wget --no-check-certificate --user=${user} --password=${password} --continue"
wgeturl=""
#... for output files
outputfolder="output/"
previewfolder="${outputfolder}preview/${polygonfile}/"
requestLog="${outputfolder}request_log.txt"
request="${outputfolder}request.sh"
originalAnswer="${outputfolder}sentinel-query.xml"
answersfile="${outputfolder}answers.txt"
wgetinput="${outputfolder}wgetinput.txt"
#... for variables which need to be declared on the fly
polygon=""
count=""
answerS2A=""
answerUUID=""
answerSize=""
answerCloud=""
answers=""
S2A=""
UUID=""
start="0"
rows="20"

#######################################################################
# Preparing everything for clean start                                #
#######################################################################
#cleanup
rm -f ${answersfile}
#reading polygon bounds
echo -e "$(tput setaf 2) Reading polygon boundaries..."
polygon=$(<${polygonfile})
echo -e " Bounds are ... [${polygon}]\n"
mkdir -p ${outputfolder}
mkdir -p ${previewfolder}

#######################################################################
# Requesting data which intersects with given polygon                 #
#######################################################################
echo -e " Requesting data from ${baseUri}...\n $(tput setaf 7)"
wgeturl="'${baseUri}/search?q=S2A* AND footprint:\"Intersects(POLYGON((${polygon})))\"&start=${start}&rows=${rows}' "
#wgeturl="'${baseUri}/search?q=S2A* AND footprint:\"Intersects(POLYGON((${polygon})))\"&start=${start}&rows=${rows}&format=json' "

discover () {
    echo ${wget} -O ${originalAnswer} ${wgeturl} > ${request}
    chmod +x ${request}
    ./${request}
    echo $(date) $(cat ${request}) >> ${requestLog}
    #extracting necessary information from response
    echo "..."
    count="$(cat ${originalAnswer} | grep -o -P '(?<=<opensearch:totalResults>).*(?=</opensearch:totalResults>)')"
    answerS2A="$(cat ${originalAnswer} | grep -o -P '(?<=<str name="filename">).*(?=.SAFE</str>)')"
    answerUUID="$(cat ${originalAnswer} | grep -o -P '(?<=<id>).*(?=</id>)' | tail -n +2)"
    answerSize="$(cat ${originalAnswer} | grep -o -P '(?<=<str name="size">).*(?=</str>)')"
    answerCloud="$(cat ${originalAnswer} | grep -o -P '(?<=<double name="cloudcoverpercentage">).*(?=</double>)')"
    paste -d ',' <(echo "${answerS2A}") <(echo "${answerUUID}") <(echo "${answerSize}") <(echo "${answerCloud}") >> ${answersfile}
    answers="NAME										| UUID		 			| SIZE | CLOUDCOVERAGE\n"
    answers="$answers$(paste -d '	' <(echo "${answerS2A}") <(echo "${answerUUID}") <(echo "${answerSize}") <(echo "${answerCloud}"))"
    rm ${originalAnswer}
}

discover
# if there is no data found
if [[ ${count} < "1" ]]
then
echo -e "$(tput setaf 2) There is no data available in the selected region. Count is ${count}\n"
exit
fi
#TODO test if there is a mistake returned by the request
#else there is data found
echo -e "$(tput setaf 2) There are ${count} files available in the selected region:\n"
echo -e "${answers}\n $(tput setaf 7)"


#######################################################################
# Requesting more data										                   #
#######################################################################
discovermore (){
while (( ${count} > $((${start} + ${rows})) )); do
    start=$((${start} + ${rows}))
    echo
    read -p "$(tput setaf 6) Request ${rows} more? $(tput bold)(y/n)$(tput sgr0)" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        echo -e "\n $(tput setaf 6) Requesting from $((${start}+1)) to $((${start} + ${rows})) $(tput setaf 7) \n"
        wgeturl="'${baseUri}/search?q=S2A* AND footprint:\"Intersects(POLYGON((${polygon})))\"&start=${start}&rows=${rows}' "
        discover
        echo -e "$(tput setaf 2) ${answers}\n $(tput setaf 7)"
    fi
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        return
    fi
done
}
discovermore
echo -e "$(tput setaf 2) You requested all available data\n $(tput setaf 7)"


#######################################################################
# Requesting each UUID for each data for download                     #
#######################################################################
echo
read -p "$(tput setaf 6) Do you want to list all requested UUIDs? $(tput bold)(y/n)$(tput sgr0)$(tput setaf 7)" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    while IFS=, read -r S2A UUID SIZE CLOUD; do
        echo -e "${UUID} $(tput setaf 7)"
    done < ${answersfile}
fi


#######################################################################
# Request a preview image for each file                               #
#######################################################################
echo
echo -n "$(tput setaf 6) Do you want to download ALL preview images from the data you requested?"
read -p "\n FYI: around 200 don't take long... $(tput bold)(y/n)$(tput sgr0)" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    while IFS=, read -r S2A UUID SIZE CLOUD; do
        #generating download links
        echo -e "$(tput setaf 2)..."
        wgeturl="${baseUri}/odata/v1/Products('${UUID}')/Products('Quicklook')/\$value"
        echo ${wgeturl} > ${wgetinput}
        echo "$(date) ${wget} -O ${previewfolder}preview_${UUID}.jpeg -i ${wgetinput}" >> ${requestLog}
        echo "${wget} -O ${previewfolder}preview_${UUID}.jpeg -i ${wgetinput}" > ${request}
        echo -e "Download request for ${S2A} is: \n  $(cat ${request})"
        echo -e "and input is $(cat ${wgetinput}) $(tput setaf 7)"
        ./${request}
    done < ${answersfile}
fi

#######################################################################
# Request the real big data, one file after another                   #
# ... as scihub only allows two concurrent downloads anyway           #
#######################################################################
echo
read -p "$(tput setaf 6) Do you want to start/continue the download? $(tput bold)(y/n)$(tput sgr0) $(tput setaf 7)" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    while IFS=, read -r S2A UUID SIZE CLOUD; do
        #generating download links
        echo -e "$(tput setaf 2)..."
        wgeturl="${baseUri}/odata/v1/Products('${UUID}')/\$value"
        echo ${wgeturl} > ${wgetinput}
        echo "$(date) ${wget} -O ${outputfolder}${S2A} -i ${wgetinput}" >> ${requestLog}
        echo "${wget} -O ${outputfolder}${S2A} -i ${wgetinput}" > ${request}
        echo -e "Download request for ${S2A} is: \n  $(cat ${request})"
        echo -e "and input is $(cat ${wgetinput}) $(tput setaf 7)"
        ./${request}
    done < ${answersfile}
fi


#######################################################################
# Cleanup at the end                                                  #
#######################################################################
echo
read -p "$(tput setaf 6) Do you want to clean up? $(tput bold)(y/n)$(tput sgr0) $(tput setaf 7)" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    rm -f ${request} ${wgetinput}
    rm -f ${originalAnswer}
    rm -f ${answersfile}
fi
