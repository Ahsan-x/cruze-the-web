#!/bin/bash

domain=""
dir=""

logo(){
echo $'\e[1;31m'"
  ____ ____  _   _ __________ 
 / ___|  _ \| | | |__  / ____|
| |   | |_) | | | | / /|  _|  
| |___|  _ <| |_| |/ /_| |___ 
 \____|_| \_\\\___//____|_____|
                              The Web " $'\e[0m'
}

initDefaults(){
  domain=$1
  if [ -z "$1" ]; then
    echo -e "\e[91mNo argument supplied\e[0m"
    echo -e "\e[91mDomain Name requried! \e[0m Ex: ./cruze.sh example.com"
    exit 1
  fi
  echo -e "\e[96mThe Target is \e[0m \e[96m$1\e[0m"
  dir=$1-$(date '+%Y-%m-%d')
  dir=$(echo "$dir" | sed -r s/[^a-zA-Z0-9]+/_/g | tr A-Z a-z)
  mkdir -p $dir
}

assetFinder(){
  # assetfinder
  echo -e "\e[91m-------------------Assetfinder Started  -------------------------------------------\e[0m"
  assetfinder --subs-only $domain | tee $dir/asset_subs.txt
}

amass(){
  # amass
  echo -e "\e[91m-------------------Amass---------------------------------------------------------\e[0m"
  amass enum -d $domain -active -o amass.txt
}

subFinder(){
  # subfinder
  echo -e "\e[91m-------------------Subfinder---------------------------------------------------------\e[0m"
  subfinder -d $domain --silent -o $dir/subfinder.txt
}

rapiddns(){
  echo -e "\e[91m-------------------Rapiddns-----------------------------------------------------------\e[0m"
  curl -s "https://rapiddns.io/subdomain/$domain?full=1"| grep -oP '_blank">\K[^<]*' | grep -v http | sort -u | tee $dir/rapiddns.txt
}

groupSubdomains(){
  cat $dir/asset_subs.txt cat $domain/amass.txt $dir/subfinder.txt $dir/rapiddns.txt | sort -u > $dir/subdomains.txt
  rm $dir/asset_subs.txt
  rm $dir/subfinder.txt
  rm $dir/rapiddns.txt
  rm $dir/amass.txt
}

liveSubdomains(){
  # echo "httprobe will check for live_subdomains"
  # it will give only https domains and not http
  echo -e "\e[91m-------------------Live HTTPS Domains-----------------------------------------------------------\e[0m"
  cat $dir/subdomains.txt | httprobe -c 50 -t 3000 | sed -e 's!http\?://\S*!!g' | sort -u | tee $dir/live_subdomains.txt
}

pathFinders(){
  echo -e "\e[91m-------------------gau Scan Started--------------------------------------------------\e[0m"
  gau --subs $domain | tee $dir/gau_urls.txt

  echo -e "\e[91m-------------------hakrawler Started-------------------------------------------------\e[0m"
  cat $dir/subdomains.txt | hakrawler -depth 3 -plain | tee $dir/hakrawler.txt

  echo -e "\e[91m-------------------waybackurls Scan Started------------------------------------------\e[0m"
  cat $dir/subdomains.txt | waybackurls | tee $dir/archiveurl.txt

  # Grouping endpoints
  cat $dir/gau_urls.txt $dir/archiveurl.txt $dir/hakrawler.txt | sort -u > $dir/waybackurls.txt
}

scanSuspect(){
  echo -e "\e[91m-------------------looking for vulnerable endpoints----------------------------------\e[0m"
  mkdir $dir/paramlist
  cat $dir/waybackurls.txt | sort -u | gf redirect| httpx -silent -status-code -mc 200 | awk '{print $1}' | sort -u > $dir/paramlist/redirect.txt
  cat $dir/waybackurls.txt | sort -u | gf ssrf | httpx -silent -status-code -mc 200 | awk '{print $1}' | sort -u  > $dir/paramlist/ssrf.txt
  cat $dir/waybackurls.txt | sort -u | gf rce | httpx -silent -status-code -mc 200 | awk '{print $1}' | sort -u   > $dir/paramlist/rce.txt
  cat $dir/waybackurls.txt | sort -u | gf idor | httpx -silent -status-code -mc 200 | awk '{print $1}' | sort -u > $dir/paramlist/idor.txt
  cat $dir/waybackurls.txt | sort -u | gf sqli | httpx -silent -status-code -mc 200 | awk '{print $1}' | sort -u > $dir/paramlist/sqli.txt
  cat $dir/waybackurls.txt | sort -u | gf lfi | httpx -silent -status-code -mc 200 | awk '{print $1}' | sort -u > $dir/paramlist/lfi.txt
  cat $dir/waybackurls.txt | sort -u |gf ssti | httpx -silent -status-code -mc 200 | awk '{print $1}' | sort -u > $dir/paramlist/ssti.txt
  cat $dir/waybackurls.txt | sort -u |gf debug_logic | httpx -silent -status-code -mc 200 | awk '{print $1}' | sort -u > $dir/paramlist/debug_logic.txt
  cat $dir/waybackurls.txt | sort -u |gf interestingsubs | httpx -silent -status-code -mc 200 | awk '{print $1}' | sort -u > $dir/paramlist/interestingsubs.txt
  cat $dir/waybackurls.txt | sort -u |grep "=" | httpx -silent -status-code -mc 200 | awk '{print $1}' | sort -u | tee $dir/domainParam.txt

  #this is the worst way!!!
  ls $dir/paramlist/ > $dir/gf-endpoints.txt && cat $dir/gf-endpoints.txt | while read endpoints; do echo $endpoints; cat $dir/paramlist/$endpoints; done
  echo -e "\e[91m-------------------Gf patters Scan Completed------------------------------------------------\e[0m"
}

wafDetect(){
  #wafw00f
  wafw00f -i $dir/live_subdomains.txt -o $dir/waf.txt
}

corsDetect(){
  #corsy
  python3 ~/tools/Corsy/corsy.py -i $dir/live_subdomains.txt -o $dir/corsy.json
}


end(){
  echo  -e "\e[91m------------------Now don't forget to use the below commands.--------------------------\e[0m"
  echo .
  echo "ffuf -w ~/tools/raft-wordlist/raft-large-directories.txt -u $dir/FUZZ -t 200"
  echo .
  echo "sudo nmap -iL $dir/live_ip.txt -A | tee $dir/nmap_scan.txt"
  echo .
  echo "sudo masscan -iL $dir/live_ip.txt -p 1-65535 --rate 10000 -oL $dir/masscan_output.json"
  echo .
  echo "python3 ~/tools/dirsearch/dirsearch.py -L $dir/subdomains.txt -e php,asp,aspx,jsp,html,zip,bak,old,backup,bak_old,js,env,config  --plain-text-report=dir_results.txt"

}

# pre
logo
initDefaults "$1"

# subdomain hunt 
assetFinder
subFinder
rapiddns
groupSubdomains
liveSubdomains

# path trace
pathFinders

# scan for suspected urls
scanSuspect

# waf
wafDetect

# CORS
corsDetect

# footer
end
