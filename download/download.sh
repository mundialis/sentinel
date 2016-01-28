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
echo "$(tput setaf 6)Please enter Username for ESAs Scihub: "
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
outputfolder="output/${polygonfile}/"
previewfolder="${outputfolder}preview/"
geometryfolder="${outputfolder}geoms/"
requestLog="${outputfolder}request_log.txt"
request="${outputfolder}request.sh"
originalAnswer="${outputfolder}sentinel-query.xml"
answersfile="${outputfolder}answers.csv"
answersunclouded="${outputfolder}answersunclouded.csv"
wgetinput="${outputfolder}wgetinput.txt"
#... for variables which need to be declared on the fly
polygon=""
count=""
newcount=""
answerS2A=""
answerUUID=""
answerSize=""
answerCloud=""
answersWkt=""
answers=""
S2A=""
UUID=""
start="0"
rows="20"
ol3wkt="${geometryfolder}ol3wkt.js"

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
mkdir -p ${geometryfolder}

#######################################################################
# Requesting data which intersects with given polygon                 #
#######################################################################
#count available data
echo -e " Counting available data from ${baseUri}...\n $(tput setaf 7)"
wgeturl="'${baseUri}/search?q=S2A* AND footprint:\"Intersects(POLYGON((${polygon})))\"&start=${start}&rows=1' "
echo ${wget} -O ${originalAnswer} ${wgeturl} > ${request}
chmod +x ${request}
./${request}
echo $(date) $(cat ${request}) >> ${requestLog}
#extracting necessary information from response
echo "..."
count="$(cat ${originalAnswer} | grep -o -P '(?<=<opensearch:totalResults>).*(?=</opensearch:totalResults>)')"
echo -e "$(tput setaf 2) There are ${count} files available in the selected region:\n"

#ask, how much data should be requested
echo
read -p "$(tput setaf 6) Do you want to request all available data at once? $(tput bold)(y/n)$(tput sgr0)$(tput setaf 7)" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    rows=${count}
else
    echo -e "\n $(tput setaf 6) How many do you want to request at once?$(tput sgr0)"
    read rows
fi

#request the data
echo -e "$(tput setaf 2) Requesting data from ${baseUri}...\n $(tput setaf 7)"
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
    answersWkt="$(cat ${originalAnswer} | grep -o -P '(?<=<str name="footprint">).*(?=</str>)')"
    paste -d ',' <(echo "${answerS2A}") <(echo "${answerUUID}") <(echo "${answerSize}") <(echo "${answerCloud}") <(echo "${answersWkt}") >> ${answersfile}
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
echo -e "$(tput setaf 2) ${answers}\n $(tput setaf 7)"


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
        echo -e "\n $(tput setaf 2) Requesting from $((${start}+1)) to $((${start} + ${rows})) $(tput setaf 7) \n"
        wgeturl="'${baseUri}/search?q=S2A* AND footprint:\"Intersects(POLYGON((${polygon})))\"&start=${start}&rows=${rows}' "
        discover
        echo -e "$(tput setaf 2) ${answers}\n $(tput setaf 7)"
    fi
    if [[ ! $REPLY =~ ^[Yy]$ ]]
    then
        return
    fi
done
echo -e "$(tput setaf 2) You requested all available data\n $(tput setaf 7)"
}
discovermore


#######################################################################
# Decide Cloud Coverage                                               #
#######################################################################
echo "$(tput setaf 6) Up to which cloudcoverage in percent are you interested in the data?$(tput sgr0)"
read wishcloud
totalsize="0"
while IFS=, read -r S2A UUID SIZEFULL CLOUDFULL WKT; do
    CLOUD=${CLOUDFULL%.*}
    SIZE=${SIZEFULL%.*}
    if [[ ${CLOUD} -le ${wishcloud} ]]
    then
        echo "${S2A},${UUID},${SIZEFULL},${CLOUDFULL},${WKT}" >> ${answersunclouded}
        if [[ ${SIZE} -ge "99" ]]
        then
            SIZE="1"
        fi
        totalsize=$((${totalsize} + ${SIZE}))
    fi
done < ${answersfile}
newcount="$(cat ${answersunclouded} | wc -l )"
echo -e "$(tput setaf 2) There are ${newcount} files left with a total size of more than ${totalsize} GB\n$(tput sgr0)"


#######################################################################
# Extract preview geometries and ol-ready-copy-paste-text             #
#######################################################################
echo
echo -n "$(tput setaf 6) Do you want to extract ALL preview geometries from the data you requested?"
read -p "\n ... $(tput bold)(y/n)$(tput sgr0)" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    #generate openlayer3 snippet for copy-paste in browser       
    echo "var format = new ol.format.WKT();" >> ${ol3wkt}
    while IFS=, read -r S2A UUID SIZE CLOUD WKT; do
        #generate wkts for each S2A-file        
        echo ${WKT} > ${geometryfolder}${UUID}.wkt
        #write echos to ol snippet
        echo "var feature = format.readFeature('${WKT}');" >> ${ol3wkt}
        echo "feature.getGeometry().transform('EPSG:4326', 'EPSG:3857');" >> ${ol3wkt}
        echo "var vector = new ol.layer.Vector({" >> ${ol3wkt}
        echo "name: '${UUID}'," >> ${ol3wkt}
        echo "source: new ol.source.Vector({" >> ${ol3wkt}
        echo "features: [feature] }) })" >> ${ol3wkt}
        echo "map.addLayer(vector)" >> ${ol3wkt}
    done < ${answersunclouded}
    echo -e "$(tput setaf 2) All Polygons saved"
fi


#######################################################################
# Requesting each UUID for each data for download                     #
#######################################################################
echo
read -p "$(tput setaf 6) Do you want to list all requested data? $(tput bold)(y/n)$(tput sgr0)$(tput setaf 7)" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo -e "$(tput setaf 2) $(cat ${answersunclouded}) $(tput setaf 7)"
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
    done < ${answersunclouded}
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
    done < ${answersunclouded}
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
    rm -f ${answersunclouded}
fi