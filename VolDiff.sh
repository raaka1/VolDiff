#!/bin/bash
# VolDiff malware analysis script by @aim4r

version="1.2.0"

################################ PRINT VOLDIFF BANNER ################################
echo -e " _    __      ______  _ ________"
echo -e "| |  / /___  / / __ \(_) __/ __/"
echo -e "| | / / __ \/ / / / / / /_/ /_  "
echo -e "| |/ / /_/ / / /_/ / / __/ __/  "
echo -e "|___/\____/_/_____/_/_/ /_/     "

echo -e "\nVolDiff: Malware Memory Footprint Analysis (v$version)"

################################ HELP ################################
if [[ $@ =~ "--help" ]] ; then
  echo -e "\nUsage: ./VolDiff.sh [BASELINE_IMAGE] INFECTED_IMAGE PROFILE [OPTIONS]"
  echo -e "\nUse directions:"
  echo -e "1. Capture a memory dump of a clean Windows system and save it as \"baseline.raw\". This image will serve as a baseline for the analysis."
  echo -e "2. Execute your malware sample on the same system, then capture a second memory dump and save it as \"infected.raw\"."
  echo -e "3. Run VolDiff as follows: \"./VolDiff.sh baseline.raw infected.raw <profile>\" where <profile> is Win7SP0x86 or Win7SP1x64 etc."
  echo -e "VolDiff will save the output of a selection of volatility plugins for both memory images (baseline and infected), then it will create a report to highlight notable changes (new processes, network connections, injected code, suspicious drivers etc)."
  echo -e "\nVolDiff can also be used to analyse a single memory image."
  echo -e "\nOptions:"
  echo -e "--help            display this help and exit"
  echo -e "--version         display version information and exit"
  echo -e "--dependencies    display information about script dependencies and exit"
  echo -e "--malware-checks  hunt and report suspicious anomalies (slow, recommended)"
  echo -e "--no-report       do not create a report"
  echo -e "\nTested using Volatility 2.4 (vol.py) on Windows 7 images."
  echo -e "Report bugs to houcem.hachicha[@]gmail.com"
  exit
fi

################################ VERSION INFORMATION ################################
if [[ $@ =~ "--version" ]] ; then
  echo -e "This is free software: you are free to change and redistribute it."
  echo -e "There is NO WARRANTY, to the extent permitted by law."
  echo -e "Written by @aim4r. Report bugs to houcem.hachicha[@]gmail.com."
  exit
fi

################################ DEPENDENCIES ################################
if [[ $@ =~ "--dependencies" ]] ; then
  echo -e "Requires volatility 2.4 (vol.py) to be installed."
  exit
fi

################################ DECLARING LIST OF VOLATILITY PLUGINS TO PROCESS ################################
# volatility plugins to run:
declare -a plugins_to_run=("handles" "psxview" "netscan" "iehistory" "getsids" "pslist" "psscan" "cmdline" "consoles" "dlllist" "filescan" "shimcache" "shelbags" "sessions" "messagehooks" "eventhooks" "svcscan" "envars" "mutantscan" "symlinkscan" "atoms" "atomscan" "drivermodule" "mftparser" "driverscan" "devicetree" "modules" "modscan" "unloadedmodules" "callbacks" "ldrmodules" "privs" "hashdump" "orphanthreads" "malfind" "idt" "gdt" "driverirp" "deskscan" "timers" "gditimers" "ssdt")

# volatility plugins to report on (order matters!) / dual mode:
declare -a plugins_to_report=("pslist" "psscan" "psxview" "netscan" "iehistory" "malfind" "sessions" "privs" "messagehooks" "eventhooks" "envars" "shimcache" "shelbags" "cmdline" "consoles" "hashdump" "drivermodule" "driverscan" "driverirp" "modules" "modscan" "unloadedmodules" "devicetree" "callbacks" "orphanthreads" "mutantscan" "symlinkscan" "ssdt")

# volatility plugins to report on (order matters!) / standalone mode:
declare -a plugins_to_report_standalone=("netscan" "psscan" "psxview" "malfind" "cmdline" "consoles" "iehistory")

################################ HARDCODED REGEX EXPRESSIONS ################################
hacker_process_regex="at.exe|chtask.exe|clearev|ftp.exe|net.exe|nbtstat.exe|net1.exe|ping.exe|powershell|procdump.exe|psexec|quser.exe|reg.exe|regsvr32.exe|schtasks|systeminfo.exe|taskkill.exe|timestomp|winrm|wmic|xcopy.exe"
hacker_dll_regex="mimilib.dll|sekurlsa.dll|wceaux.dll|iamdll.dll"

# suspicious process names
l33t_process_name="snss|crss|cssrs|csrsss|lass|isass|lssass|lsasss|scvh|svch0st|svhos|svchst|svchosts|lsn|g0n|l0g|nvcpl|rundii|wauclt|spscv|spppsvc|sppscv|sppcsv|taskchost|tskhost|msorsv|corsw|arch1ndex|wmipvr|wmiprse|runddl"

# usual process list
usual_processes="sppsvc.exe|audiodg.exe|mscorsvw.exe|SearchIndexer|TPAutoConnSvc|TPAutoConnect|taskhost.exe|smss.exe|crss.exe|wininit.exe|services.exe|lsass.exe|svchost.exe|lsm.exe|explorer.exe|winlogon|conhost.exe|dllhost.exe|spoolsv.exe|vmtoolsd.exe|WmiPrvSE.exe"

# regexes used to analyse imports
password_extract_imports="SamLookupDomainInSamServer|NlpGetPrimaryCredential|LsaEnumerateLogonSessions|SamOpenDomain|SamOpenUser|SamGetPrivateData|SamConnect|SamRidToSid|PowerCreateRequest|SeDebugPrivilege|SystemFunction006|SystemFunction040"
process_injection_imports="VirtualAllocEx|AllocateVirtualMemory|VirtualProtectEx|ProtectVirtualMemory|CreateProcess|LoadLibrary|LdrLoadDll|CreateToolhelp32Snapshot|QuerySystemInformation|EnumProcesses|WriteProcessMemory|WriteVirtualMemory|CreateRemoteThread|ResumeThread|SetThreadContext|SetContextThread|QueueUserAPC|QueueApcThread|WinExec"
web_imports="DeleteUrlCacheEntry|CreateUrlCacheEntry|HttpSendRequestA|HttpSendRequestW|HttpSendRequestExA|HttpSendRequestExW|URLDownloadToFileA|WSASocket|WSASend|WSARecv|WS2_32"
service_imports="CreateService|StartService|NdrClientCall2|NtLoadDriver"
uac_bypass_imports="AllocateAndInitializeSid|EqualSid|RtlQueryElevationFlags|GetTokenInformation|GetSidSubAuthority|GetSidSubAuthorityCount"
anti_debug_imports="CheckRemoteDebugger|DebugActiveProcess|FindWindow|GetLastError|GetWindowThreadProcessId|IsDebugged|IsDebuggerPresent|NtCreateThreadEx|NtGlobalFlags|NtSetInformationThread|OutputDebugString|pbIsPresent|Process32First|Process32Next|TerminateProcess|ThreadHideFromDebugger|UnhandledExceptionFilter|ZwQueryInformation"
misc_imports="CreateFile|NtSetSystemInformation|NtQuerySystemInformation|GetCurrentProcess|GetStartupInfo|GlobalAddAtomA|Sleep|RegOpenKeyEx|RegQueryValueEx|GetModuleFileName|WriteFile"

# regexes used to analyse strings (from process executables)
web_regex_str="cookie|download|mozilla|post|proxy|responsetext|socket|useragent|user-agent|urlmon|user_agent|WebClient|winhttp|http"
antivirus_regex_str="antivir|avast|avcons|avgctrl|avginternet|avira|bitdefender|checkpoint|comodo|F-Secure|firewall|kaspersky|mcafee|norton|norman|safeweb|sophos|symantec|windefend"
virtualisation_regex_str="000569|001C14|080027|citrix|parallels|proxmox|qemu|SbieDll|Vbox|VMXh|virm|virtualbox|virtualpc|vmsrvc|vpc|winice|vmware|xen"
sandbox_regex_str="anubis|capturebat|cuckoo|deepfreeze|debug|fiddler|fireeye|noriben|perl|python|sandb|schmidti|snort|tcpdump|wireshark"
sysinternals_regex_str="filemon|sysinternal|procmon|psexec|regmon|sysmon"
shell_regex_str="shellexecute|shell32"
keylogger_regex_str="backspace|klog|keylog|shift"
filepath_regex_str='C:\\(?:[^\\/:*?"<>|\r\n]+\\)*[^\\/:*?"<>|\r\n]*'
password_regex_str="brute|credential|creds|mimikatz|passwd|password|pwd|sniff|stdapi|WCEServicePipe|wce_krbtkts"
powershell_regex_str="powerview|powershell"
infogathering_regex_str="gethost|wmic|GetVolumeInformation"
banking_regex_str="banc|banco|bank|Barclays|hsbc|jpmorgan|lloyds|natwest|paypal|santander"
socialsites_regex_str="facebook|instagram|linkedin|twitter|yahoo|youtube"
exec_regex_str="\.bat|\.cmd|\.class|\.exe|\.jar|\.js|\.jse|\.SCR|\.VBE|\.vbs"
crypto_regex_str="bitlocker|crypt|truecrypt|veracrypt"
other_regex_str="admin|backdoor|botnet|chrome|clearev|currentversion|firefox|hosts|login|malware|netsh|registry|rootkit|sleep|smtp|timestomp|torrent|Trojan|UserInit"

################################ RUNNING MODE ################################
if [[ -f $2 ]] ; then
  mode="dual"
else
  mode="standalone"
fi

################################################################## ENTER DUAL MODE ################################################################## 

################################ SETTING PROFILE AND FINDING PATH TO MEMORY IMAGES ################################
if [[ $mode = "dual" ]] ; then 
  if [[ -f $1 ]] ; then
    baseline_memory_image=$1
    echo -e "Path to baseline memory image: $baseline_memory_image..."
  elif [[ -f baseline.raw ]] ; then
    baseline_memory_image=baseline.raw
    echo -e "Path to baseline memory image is not valid or was not specified. Using default ($baseline_memory_image)..."
  elif [[ -f baseline.vmem ]] ; then
    baseline_memory_image=baseline.vmem
    echo -e "Path to baseline memory image is not valid or was not specified. Using default ($baseline_memory_image)..."
  else
    echo -e "Please specify a path to a baseline memory image."
    exit
  fi

  if [[ -f $2 ]]; then
    infected_memory_image=$2
    echo -e "Path to infected memory image: $infected_memory_image..."
  elif [[ -f infected.raw ]] ; then
    infected_memory_image=infected.raw
    echo -e "Path to infected memory image is not valid or was not specified. Using default ($infected_memory_image)..."
  elif [[ -f infected.vmem ]] ; then
    infected_memory_image=infected.vmem
    echo -e "Path to infected memory image is not valid or was not specified. Using default ($infected_memory_image)..."
  else
    echo -e "Please specify a path to a memory image of an infected system."
    exit
  fi

  if [[ -z $3 ]] ; then
    profile=Win7SP0x86
    echo -e "Profile is not specified. Using default ($profile)..."
  elif [[ $3 != Win7SP1x64 ]] &&  [[ $3 != Win7SP0x86 ]] &&  [[ $3 != Win7SP0x64 ]] &&  [[ $3 != Win7SP1x86 ]] ; then
    profile=$3
    echo -e "WARNING: This script was only tested using Windows 7 profiles. The specified profile ($profile) seems different!" 
  else
    profile=$3
    echo -e "Profile: $profile..."
  fi

  ################################ CREATING FOLDER TO STORE OUTPUT ################################
  starttime=$(date +%s)
  output_dir=VolDiff_$(date +%F_%R)
  mkdir $output_dir
  mkdir $output_dir/tmpfolder

  ################################ RUNNING VOLATILITY PLUGINS ################################
  echo -e "Running a selection of volatility plugins (time consuming)..."
  for plugin in "${plugins_to_run[@]}" 
  do
    echo -e "Volatility plugin "$plugin" execution in progress..."
    mkdir $output_dir/$plugin
    if [[ $plugin = "mutantscan" ]] || [[ $plugin = "handles" ]] || [[ $plugin = "privs" ]]  || [[ $plugin = "envars" ]] ; then
      vol.py --profile=$profile -f $baseline_memory_image $plugin --silent &> $output_dir/$plugin/baseline-$plugin.txt &
      vol.py --profile=$profile -f $infected_memory_image $plugin --silent &> $output_dir/$plugin/infected-$plugin.txt &
      wait
    elif [[ $plugin = "orphanthreads" ]]  ; then
      vol.py --profile=$profile -f $baseline_memory_image threads -F OrphanThread &> $output_dir/orphanthreads/baseline-orphanthreads.txt &
      vol.py --profile=$profile -f $infected_memory_image threads -F OrphanThread &> $output_dir/orphanthreads/infected-orphanthreads.txt &
      wait
    elif [[ $plugin = "psxview" ]]  ; then
      vol.py --profile=$profile -f $baseline_memory_image psxview -R &> $output_dir/psxview/baseline-psxview.txt &
      vol.py --profile=$profile -f $infected_memory_image psxview -R &> $output_dir/psxview/infected-psxview.txt &
      wait
    elif [[ $plugin = "malfind" ]] ; then
      mkdir $output_dir/$plugin/dump-dir-baseline
      mkdir $output_dir/$plugin/dump-dir-infected
      vol.py --profile=$profile -f $baseline_memory_image $plugin -D $output_dir/$plugin/dump-dir-baseline &> $output_dir/$plugin/baseline-$plugin.txt &
      vol.py --profile=$profile -f $infected_memory_image $plugin -D $output_dir/$plugin/dump-dir-infected &> $output_dir/$plugin/infected-$plugin.txt &
      wait
    else
      vol.py --profile=$profile -f $baseline_memory_image $plugin &> $output_dir/$plugin/baseline-$plugin.txt &
      vol.py --profile=$profile -f $infected_memory_image $plugin &> $output_dir/$plugin/infected-$plugin.txt &
      wait
    fi
  done
  wait

  ################################ DIFFING VOLATILITY RESULTS ################################
  echo -e "Diffing output results..."
  for plugin in "${plugins_to_run[@]}"
  do
    diff $output_dir/$plugin/baseline-$plugin.txt $output_dir/$plugin/infected-$plugin.txt | grep -E "^>" | sed 's/^..//' &> $output_dir/$plugin/diff-$plugin.txt
  done

  ################################ DUMPING NEW PROCESSES TO DISK ################################
  echo -e "Dumping new processes to disk..."
  cat $output_dir/psscan/diff-psscan.txt | tr -s ' ' | cut -d " " -f 3 | sort | uniq >  $output_dir/tmpfolder/new-procpids.tmp
  mkdir $output_dir/procdump
  while read newpid ; do
    vol.py --profile=$profile -f $infected_memory_image procdump -D $output_dir/procdump/ -p $newpid &> /dev/null
  done < $output_dir/tmpfolder/new-procpids.tmp
  wait


  if [[ $@ =~ "--malware-checks" ]] ; then
    touch $output_dir/tmpfolder/malware-checks.tmp
    echo -e "Hunting for process anomalies..."

    ################################ MALWARE CHECKS - NETWORK ################################

    # compute unique IPs from netscan output:
    cat $output_dir/netscan/diff-netscan.txt | grep -o -E "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | sort | uniq | grep -v -E "127\.0\.0\.1|0\.0\.0\.0" > $output_dir/tmpfolder/netscan-uniq-ips.tmp
    if [[ -s $output_dir/tmpfolder/netscan-uniq-ips.tmp ]]; then
      echo -e "\n\nUnique IP addresses from netscan output." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/netscan-uniq-ips.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    ################################ MALWARE CHECKS - PROCESS ANOMALIES ################################

    # verify PID of System process = 4
    cat $output_dir/psscan/infected-psscan.txt | grep " System " | tr -s ' ' | cut -d " " -f 3 > $output_dir/tmpfolder/system-pids.tmp
    while read pid; do
      if [[ $pid != "4" ]] ; then
        echo -e "\nSuspicious 'System' process running with PID $pid (expected PID is 4)." >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    done < $output_dir/tmpfolder/system-pids.tmp

    # verify that only one instance of certain processes is running:
    for process in " services.exe" " System" " wininit.exe" " smss.exe" " lsass.exe" " lsm.exe" " explorer.exe"; do
      if [[ "$(cat $output_dir/psscan/infected-psscan.txt | grep $process | wc -l)" != "1" ]] ; then
        echo -e "\n\nMultiple instances of$process were detected." >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
        sed -n '2p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
        sed -n '3p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
        cat $output_dir/psscan/infected-psscan.txt | grep $process >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    done

    # verify that some processes do not have a child:
    for process in "lsass.exe" "lsm.exe"; do
      cat $output_dir/psscan/infected-psscan.txt | grep $process | tr -s ' ' | cut -d " " -f 3 >> $output_dir/tmpfolder/cpids.tmp
    done
    cat $output_dir/psscan/infected-psscan.txt | tr -s ' ' | cut -d " " -f 4 >> $output_dir/tmpfolder/ppids.tmp
    while read pid; do
      while read ppid; do
        if [[ "$pid" == "$ppid" ]]; then
          echo -e "\n\nProcess with (PID $ppid) is not supposed to be a parent." >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
          sed -n '2p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
          sed -n '3p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
          cat $output_dir/psscan/infected-psscan.txt | grep " $ppid " >> $output_dir/tmpfolder/malware-checks.tmp
        fi
      done < $output_dir/tmpfolder/ppids.tmp
    done < $output_dir/tmpfolder/cpids.tmp

    # verify child/parent process relationships:
    for child in " svchost.exe" " smss.exe" " conhost.exe" " audiodg.exe" " services.exe" " lsass.exe" " lsm.exe" " taskhost.exe" " spoolsv.exe" " sppsvc.exe" " taskhost.exe" " mscorsvw.exe" " TPAutoConnSvc" " SearchIndexer" " WmiPrvSE.exe" ; do
      if [[ $child = " sppsvc.exe" ]] || [[ $child = " taskhost.exe" ]] || [[ $child = " mscorsvw.exe" ]] || [[ $child = " TPAutoConnSvc" ]] || [[ $child = " SearchIndexer" ]] || [[ $child = " svchost.exe" ]] || [[ $child = " taskhost.exe" ]] || [[ $child = " spoolsv.exe" ]] ; then parent=" services.exe"; fi
      if [[ $child = " smss.exe" ]]; then parent=" System"; fi
      if [[ $child = " conhost.exe" ]]; then parent=" csrss.exe"; fi
      if [[ $child = " WmiPrvSE.exe" ]] || [[ $child = " audiodg.exe" ]] ; then parent=" svchost.exe"; fi
      if [[ $child = " services.exe" ]] || [[ $child = " lsass.exe" ]] || [[ $child = " lsm.exe" ]]; then parent=" wininit.exe"; fi
      if grep $child $output_dir/psscan/infected-psscan.txt > /dev/null ; then
        if [[ "$(cat $output_dir/psscan/infected-psscan.txt | grep $parent | wc -l)" = "1" ]] ; then
          cat $output_dir/psscan/infected-psscan.txt | grep $child | tr -s ' ' | cut -d " " -f 4 > $output_dir/tmpfolder/child-ppids.tmp
          parent_pid="$(cat $output_dir/psscan/infected-psscan.txt | grep $parent | tr -s ' ' | cut -d ' ' -f 3)"
          while read ppid; do
            ppid=$( printf $ppid )
            parent_pid=$( printf $parent_pid )
            if [[ $ppid != $parent_pid ]] ; then
              tail -n +4 $output_dir/psscan/infected-psscan.txt | tr -s ' ' | cut -d ' ' -f 2-3 | grep -i " "$ppid | cut -d ' ' -f 1 | sort | uniq > $output_dir/tmpfolder/ppidprocess.tmp
              if [[ -s $output_dir/tmpfolder/ppidprocess.tmp ]] ; then   
                ppidlines=`cat $output_dir/tmpfolder/ppidprocess.tmp | wc -l`  &> /dev/null
                if [[ $ppidlines = 1 ]] ; then
                  echo -e "\n\nUnexpected parent process for$child: PPID $ppid (`cat $output_dir/tmpfolder/ppidprocess.tmp`) instead of PPID $parent_pid ($parent )." >> $output_dir/tmpfolder/malware-checks.tmp
                  echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
                  sed -n '2p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
                  sed -n '3p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
                  cat $output_dir/psscan/infected-psscan.txt | grep " $ppid " >> $output_dir/tmpfolder/malware-checks.tmp
                else
                  cat $output_dir/tmpfolder/ppidprocess.tmp | tr '\n' ' ' > $output_dir/tmpfolder/ppparents.tmp
                  echo -e "\n\nUnexpected parent process for$child: PPID $ppid ( multiple associated processes: `cat $output_dir/tmpfolder/ppparents.tmp`) instead of PPID $parent_pid ($parent )." >> $output_dir/tmpfolder/malware-checks.tmp
                  echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
                  sed -n '2p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
                  sed -n '3p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
                  cat $output_dir/psscan/infected-psscan.txt | grep " $ppid " >> $output_dir/tmpfolder/malware-checks.tmp
                fi
              else
                echo -e "\n\nUnexpected parent process for$child: PPID $ppid (could not map associated process name) instead of PPID $parent_pid ($parent )." >> $output_dir/tmpfolder/malware-checks.tmp
                echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
                sed -n '2p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
                sed -n '3p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
                cat $output_dir/psscan/infected-psscan.txt | grep " $ppid " >> $output_dir/tmpfolder/malware-checks.tmp
              fi
            fi     
          done < $output_dir/tmpfolder/child-ppids.tmp
        fi
      fi
    done

    # verify that every process has a parent (except for explorer.exe, csrss.exe, wininit.exe and winlogon.exe)
    mkdir $output_dir/tmpfolder/ppids
    tail -n +4 $output_dir/psscan/infected-psscan.txt | tr -s ' ' | cut -d ' ' -f 4 | sort | uniq | grep -v "^0$" > $output_dir/tmpfolder/ppids/ppids.temp
    tail -n +4 $output_dir/psscan/infected-psscan.txt | tr -s ' ' | cut -d ' ' -f 3 | sort | uniq > $output_dir/tmpfolder/ppids/pids.temp
    while read ppid; do 
      if ! grep -E "^$ppid$" $output_dir/tmpfolder/ppids/pids.temp > /dev/null ; then
        tail -n +4 $output_dir/psscan/infected-psscan.txt | tr -s ' ' | cut -d ' ' -f 2,3,4 | grep -E " $ppid$" | cut -d ' ' -f 1 | sort | uniq > $output_dir/tmpfolder/ppids/processes-$ppid.temp
        cat $output_dir/tmpfolder/ppids/processes-$ppid.temp | tr '\n' ' ' > $output_dir/tmpfolder/ppids/processes-$ppid-space.temp
        if  ! grep -E -i "explorer.exe|csrss.exe|wininit.exe|winlogon.exe" $output_dir/tmpfolder/ppids/processes-$ppid-space.temp > /dev/null ; then 
          echo -e "\n\nPPID $ppid does not have an associated process." >> $output_dir/tmpfolder/malware-checks.tmp
          echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
          sed -n '2p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
          sed -n '3p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
          cat $output_dir/psscan/infected-psscan.txt | grep " $ppid " >> $output_dir/tmpfolder/malware-checks.tmp
        fi 
      fi
    done < $output_dir/tmpfolder/ppids/ppids.temp

    # verify processes are running in expected sessions:
    for process in " wininit.exe" " services.exe" " lsass.exe" " svchost.exe" " lsm.exe" " winlogon.exe" ; do
      if [[ $process = " csrss.exe" ]] || [[ $process = " wininit.exe" ]] || [[ $process = " services.exe" ]] || [[ $process = " lsass.exe" ]] || [[ $process = " svchost.exe" ]]|| [[ $process = " lsm.exe" ]]; then session="0" ; fi
      if [[ $process = " winlogon.exe" ]]; then session="1" ; fi
      cat $output_dir/pslist/infected-pslist.txt | grep $process | tr -s ' ' | cut -d ' ' -f 7 > $output_dir/tmpfolder/process_sessions.tmp
      while read psession ; do
        if [[ $psession != $session ]] ; then
          echo -e "\n\nProcess$process running in unexpected session ($psession instead of $session)." >> $output_dir/tmpfolder/malware-checks.tmp
          echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
          sed -n '2p' $output_dir/pslist/infected-pslist.txt >> $output_dir/tmpfolder/malware-checks.tmp
          sed -n '3p' $output_dir/pslist/infected-pslist.txt >> $output_dir/tmpfolder/malware-checks.tmp
          cat $output_dir/pslist/infected-pslist.txt | grep $process >> $output_dir/tmpfolder/malware-checks.tmp
        fi
      done < $output_dir/tmpfolder/process_sessions.tmp
    done

    # check process executable path:
    for process in "smss.exe" "crss.exe" "wininit.exe" "services.exe" "lsass.exe" "svchost.exe" "lsm.exe" "explorer.exe" "winlogon"; do
      if [[ $process == "smss.exe" ]]; then processpath="\systemroot\system32\smss.exe" ; fi
      if [[ $process == "crss.exe" ]]; then processpath="\windows\system32\csrss.exe" ; fi
      if [[ $process == "wininit.exe" ]]; then processpath="\windows\system32\wininit.exe" ; fi
      if [[ $process == "services.exe" ]]; then processpath="\windows\system32\services.exe" ; fi
      if [[ $process == "lsass.exe" ]]; then processpath="\windows\system32\lsass.exe" ; fi
      if [[ $process == "svchost.exe" ]]; then processpath="\windows\system32\svchost.exe" ; fi
      if [[ $process == "lsm.exe" ]]; then processpath="\windows\system32\lsm.exe" ; fi
      if [[ $process == "explorer.exe" ]]; then processpath="\windows\explorer.exe" ; fi
      if [[ $process == "winlogon.exe" ]]; then processpath="\windows\system32\winlogon.exe" ; fi
      if [[ $process == "sppsvc.exe" ]]; then processpath="\windows\system32\sppsvc.exe" ; fi
      cat $output_dir/dlllist/infected-dlllist.txt | grep -i -A 1 $process | grep "Command line" | grep -o '\\.*' | cut -d ' ' -f 1 | tr '[:upper:]' '[:lower:]' | sed 's,\\,\\\\,g' > $output_dir/tmpfolder/path_list.tmp
      if [[ -s $output_dir/tmpfolder/path_list.tmp ]]; then
        while read path; do
          if [[ "$path" != "$processpath" ]]; then
            echo -e "\n\nProcess running from unusual path." >> $output_dir/tmpfolder/malware-checks.tmp
            echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
            echo -e "Process $process is running from $path instead of $processpath" >> $output_dir/tmpfolder/malware-checks.tmp
          fi
        done < $output_dir/tmpfolder/path_list.tmp
      fi
    done

    # verify if any processes have suspicious l33t names:
    cat $output_dir/psscan/infected-psscan.txt | grep -E -i $l33t_process_name > $output_dir/tmpfolder/suspicious_process.tmp
    if [[ -s $output_dir/tmpfolder/suspicious_process.tmp ]]; then
      echo -e "\n\nProcesses with suspicious names." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/suspicious_process.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # verify if any hacker tools were used in process list:
    cat $output_dir/psscan/infected-psscan.txt | grep -E -i $hacker_process_regex > $output_dir/tmpfolder/suspicious_tools.tmp
    if [[ -s $output_dir/tmpfolder/suspicious_tools.tmp ]]; then
      echo -e "\n\nProcesses that may have been used for lateral movement, exfiltration etc." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/psscan/infected-psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/suspicious_tools.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # detect process hollowing:
    mkdir $output_dir/tmpfolder/hollowing
    vol.py --profile=$profile -f $infected_memory_image procdump -u -D $output_dir/tmpfolder/hollowing/ &> /dev/null
    cat $output_dir/psscan/infected-psscan.txt | tr -s ' ' | cut -d ' ' -f 2 | cut -d '.' -f 1 | sort | uniq > $output_dir/tmpfolder/process-names.tmp
    tail -n +4 $output_dir/tmpfolder/process-names.tmp > $output_dir/tmpfolder/procnames.tmp
    while read process ; do
      cat $output_dir/psscan/infected-psscan.txt | grep -i $process | tr -s ' ' | cut -d ' ' -f 3 > $output_dir/tmpfolder/$process-pids.tmp
      touch $output_dir/tmpfolder/$process-size.tmp
      while read pid ; do
        ls -l $output_dir/tmpfolder/hollowing/ | tr -s ' ' | cut -d ' ' -f5,9 | grep -i "executable.$pid.exe" | cut -d ' ' -f 1 >> $output_dir/tmpfolder/$process-size.tmp
      done < $output_dir/tmpfolder/$process-pids.tmp
      cat $output_dir/tmpfolder/$process-size.tmp | uniq > $output_dir/tmpfolder/$process-size-uniq.tmp
      lines=`wc -l < $output_dir/tmpfolder/$process-size-uniq.tmp`
      if [[ $lines != 1 ]] && [[ $lines != 0 ]]  ; then 
        echo -e "\n\nPotential process hollowing detected in $process (based on size)." >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "Process    PID  Size" >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "-----------------------------------" >> $output_dir/tmpfolder/malware-checks.tmp
        while read pid ; do
          echo -e "$process    $pid  `ls -l $output_dir/tmpfolder/hollowing/ | tr -s ' ' | cut -d ' ' -f5,9 | grep -i "executable.$pid.exe" | cut -d ' ' -f 1`" >> $output_dir/tmpfolder/malware-checks.tmp
        done < $output_dir/tmpfolder/$process-pids.tmp   
      fi
    done < $output_dir/tmpfolder/procnames.tmp

    # detect processes with exit time but active threads:
    cat $output_dir/psxview/diff-psxview.txt | tr -s ' ' | cut -d ' ' -f 1,2,6,13 | grep "UTC" | grep "True" | cut -d ' ' -f 1 > $output_dir/tmpfolder/exit_with_threads.tmp
    if [[ -s $output_dir/tmpfolder/exit_with_threads.tmp ]]; then
      echo -e "\n\nProcess(es) with exit time and active threads running." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/psxview/infected-psxview.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/psxview/infected-psxview.txt >> $output_dir/tmpfolder/malware-checks.tmp
      while read procname ; do 
        cat $output_dir/psxview/diff-psxview.txt | grep $procname >> $output_dir/tmpfolder/malware-checks.tmp
      done < $output_dir/tmpfolder/exit_with_threads.tmp
    fi

    # check if any process has domain or enterprise admin privileges:
    cat $output_dir/getsids/diff-getsids.txt | egrep '(Domain Admin|Enterprise Admin|Schema Admin)' > $output_dir/tmpfolder/suspicious_privlege.tmp
    if [[ -s $output_dir/tmpfolder/suspicious_privlege.tmp ]]; then
      echo -e "\n\nProcess(es) with domain or enterprise admin privileges." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/suspicious_privlege.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # check if any process has debug privileges:
    cat $output_dir/privs/diff-privs.txt | grep -i "debug" > $output_dir/tmpfolder/debug_privs.tmp
    if [[ -s $output_dir/tmpfolder/debug_privs.tmp ]]; then
      echo -e "\n\nProcess(es) with debug privileges." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/privs/infected-privs.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/privs/infected-privs.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/debug_privs.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # check if any process has a raw socket handle:
    cat $output_dir/handles/diff-handles.txt | grep -F "\Device\RawIp" > $output_dir/tmpfolder/raw_socket.tmp
    if [[ -s $output_dir/tmpfolder/raw_socket.tmp ]]; then
      echo -e "\n\nRaw socket handles." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/handles/infected-handles.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/handles/infected-handles.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/raw_socket.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # check if any process has a handle to a remote mapped share:
    cat $output_dir/handles/diff-handles.txt | grep -F "\\\\Device\\\\(LanmanRedirector|Mup)" > $output_dir/tmpfolder/remote_shares.tmp
    if [[ -s $output_dir/tmpfolder/remote_shares.tmp ]]; then
      echo -e "\n\nRemote share handles." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/handles/infected-handles.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/handles/infected-handles.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/remote_shares.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    ################################ MALWARE CHECKS - DLLs ################################

    # find suspicious new DLLs (dlllist):
    cat $output_dir/dlllist/diff-dlllist.txt | grep -o -E "C:.*.dll" | grep -v -i "System32" | uniq | sort > $output_dir/tmpfolder/dlls.tmp
    if [[ -s $output_dir/tmpfolder/dlls.tmp ]] ; then
      echo -e "\n\nNew DLLs (dlllist)." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/dlls.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find new dlls (atoms):
    cat $output_dir/atoms/diff-atoms.txt | grep -i -E ".dll$"  >> $output_dir/tmpfolder/atoms.tmp
    if [[ -s $output_dir/tmpfolder/atoms.tmp ]] ; then
      echo -e "\n\nNew DLLs (atoms)." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/atoms/infected-atoms.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/atoms/infected-atoms.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/atoms.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find new dlls (atomscan):
    cat $output_dir/atomscan/diff-atomscan.txt | grep -i -E ".dll$"  >> $output_dir/tmpfolder/atomscan.tmp
    if [[ -s $output_dir/tmpfolder/atomscan.tmp ]] ; then
      echo -e "\n\nNew DLLs (atomscan)." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/atomscan/infected-atomscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/atomscan/infected-atomscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/atomscan.tmp >> $output_dir/tmpfolder/malware-checks.tmp
      if [[ $@ =~ "--add-hints" ]] ; then
        echo -e "\nHint: The DLLs above were potentially injected to genuine processes." >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    fi

    # highlight new hidden DLLs (ldrmodules):
    cat $output_dir/ldrmodules/diff-ldrmodules.txt | grep "False" | grep -E -v -i "system32|explorer.exe|iexplore.exe|.fon$" | sort | uniq > $output_dir/tmpfolder/ldrmodules.tmp
    if [[ -s $output_dir/tmpfolder/ldrmodules.tmp ]] ; then
      echo -e "\n\nSuspicious new ldrmodules entries." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/ldrmodules/infected-ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/ldrmodules/infected-ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/ldrmodules.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find highly suspicious DLLs used for password stealing (ldrmodules):
    cat $output_dir/ldrmodules/diff-ldrmodules.txt | grep -E -i $hacker_dll_regex | sort | uniq > $output_dir/tmpfolder/ldrmodule_hacker.tmp
    if [[ -s $output_dir/tmpfolder/ldrmodule_hacker.tmp ]] ; then
      echo -e "\n\nNew DLLs that may have been used for password theft." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/ldrmodules/infected-ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/ldrmodules/infected-ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/ldrmodule_hacker.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find DLLs with no path / no name (indicates process hollowing) (ldrmodules):
    cat $output_dir/ldrmodules/diff-ldrmodules.txt | grep -E -i "no name" | sort | uniq > $output_dir/tmpfolder/ldrmodule_hollow.tmp
    if [[ -s $output_dir/tmpfolder/ldrmodule_hollow.tmp ]] ; then
      echo -e "\n\nNew DLLs with no path/name (indicates process hollowing)." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/ldrmodules/infected-ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/ldrmodules/infected-ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/ldrmodule_hollow.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    ################################ MALWARE CHECKS - FILES ################################

    # find DLLs/EXES loaded from temp folders (dlllist):
    cat $output_dir/dlllist/diff-dlllist.txt | grep -E -i "TMP|TEMP|AppData" | sort | uniq > $output_dir/tmpfolder/dlllist_temp.tmp
    if [[ -s $output_dir/tmpfolder/dlllist_temp.tmp ]] ; then
      echo -e "\n\nNew DLLs/EXEs loaded from temp folders." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/dlllist_temp.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find hidden DLLs/EXES (ldrmodules):
    cat $output_dir/ldrmodules/diff-ldrmodules.txt | grep -E -i "False  False  False" | sort | uniq | grep -E -i ".dll$|.exe$" > $output_dir/tmpfolder/ldrmodule_hidden.tmp
    if [[ -s $output_dir/tmpfolder/ldrmodule_hidden.tmp ]] ; then
      echo -e "\n\nNew hidden DLLs/EXEs (ldrmodules)." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/ldrmodules/infected-ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/ldrmodules/infected-ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/ldrmodule_hidden.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # highlight new suspicious files (filescan):
    cat $output_dir/filescan/diff-filescan.txt | grep -E -i "\\ProgramData|\\Recycle|\\Windows\\Temp|\\Users\\All|\\Users\\Default|\\Users\\Public|\\ProgramData|AppData" | sort | uniq | grep -v -E ".db$|.lnk$|.ini$|.log$" | tr -s ' ' | cut -d ' ' -f 5 | sort | uniq >> $output_dir/tmpfolder/filescan.tmp
    if [[ -s $output_dir/tmpfolder/filescan.tmp ]] ; then
      echo -e "\n\nNew files on disk." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/filescan.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # highlight prefetch files:
    cat $output_dir/mftparser/diff-mftparser.txt | grep \.pf$ | awk '{print $NF}' | sort | uniq > $output_dir/tmpfolder/prefetch.tmp
    if [[ -s $output_dir/tmpfolder/prefetch.tmp ]]; then
      echo -e "\n\nNew prefetch artifacts." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/prefetch.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # highlight binaries loaded from TEMP folders:
    cat $output_dir/envars/diff-envars.txt | grep -i "TEMP" > $output_dir/tmpfolder/temp_envars.tmp
    if [[ -s $output_dir/tmpfolder/temp_envars.tmp ]]; then
      echo -e "\n\nPossible binaries loaded from TEMP folders." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/envars/infected-envars.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/envars/infected-envars.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/temp_envars.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find suspicious new executables (dlllist):
    cat $output_dir/dlllist/diff-dlllist.txt | grep "Command line" | grep -E -v -i "system32|explorer.exe|iexplore.exe" | sed -e 's/Command line : //' | sort | uniq > $output_dir/tmpfolder/execs.tmp
    if [[ -s $output_dir/tmpfolder/execs.tmp ]] ; then
      echo -e "\n\nNew executables (dlllist)." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/execs.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # highlight alternate data stream files:
    cat $output_dir/mftparser/diff-mftparser.txt | grep "DATA ADS" > $output_dir/tmpfolder/ads.tmp
    if [[ -s $output_dir/tmpfolder/ads.tmp ]]; then
      echo -e "\n\nNew alternate Data Stream (ADS) files." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/ads.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    ################################ MALWARE CHECKS - MISC ################################

    # find interresting new entries in hosts file
    mkdir $output_dir/tmpfolder/hostsb
    mkdir $output_dir/tmpfolder/hostsi
    qaddressb=$(cat $output_dir/filescan/baseline-filescan.txt | grep -i -E "etc\\\\hosts$" | tr -s ' ' | cut -d ' ' -f 1)
    if [[ ! -z "$qaddressb" ]] ; then 
      vol.py --profile=$profile -f $baseline_memory_image dumpfiles -Q $qaddressb -D $output_dir/tmpfolder/hostsb --name &> /dev/null 
      strings $output_dir/tmpfolder/hostsb/* > $output_dir/tmpfolder/hosts_baseline.tmp  &> /dev/null
    fi
    qaddressi=$(cat $output_dir/filescan/infected-filescan.txt | grep -i -E "etc\\\\hosts$" | tr -s ' ' | cut -d ' ' -f 1)
    if [[ ! -z "$qaddressi" ]] ; then 
      vol.py --profile=$profile -f $infected_memory_image dumpfiles -Q $qaddressi -D $output_dir/tmpfolder/hostsi --name &> /dev/null 
      strings $output_dir/tmpfolder/hostsi/* > $output_dir/tmpfolder/hosts_infected.tmp  &> /dev/null
    fi
    if [[ -s $output_dir/tmpfolder/hosts_baseline.tmp ]] && [[ -s $output_dir/tmpfolder/hosts_infected.tmp ]] ; then
      diff $output_dir/tmpfolder/hosts_baseline.tmp $output_dir/tmpfolder/hosts_infected.tmp | grep -E "^>" | sed 's/^..//' &> $output_dir/tmpfolder/new-hosts.tmp
      if [[ -s $output_dir/tmpfolder/new-hosts.tmp ]] ; then
        echo -e "\n\nChanges in hosts files." >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
        cat $output_dir/tmpfolder/new-hosts.tmp >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    fi
    
    # find suspicious new desktop instances: 
    cat $output_dir/deskscan/diff-deskscan.txt | grep "Desktop:" >> $output_dir/tmpfolder/deskscan.tmp
    if [[ -s $output_dir/tmpfolder/deskscan.tmp ]] ; then
      echo -e "\n\nNew desktop instances." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/deskscan.tmp >> $output_dir/tmpfolder/malware-checks.tmp
      if [[ $@ =~ "--add-hints" ]] ; then
            echo -e "\nHint: Use wintree to view a tree of the windows in suspicious desktops." >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    fi

    ################################ MALWARE CHECKS - PERSISTENCE ################################

    echo -e "Searching for persistence artifacts..."

    # filtering svcscan results:
    cat $output_dir/svcscan/baseline-svcscan.txt | grep -i "Binary Path" | sort | uniq > $output_dir/tmpfolder/baseline-svcscan.tmp
    cat $output_dir/svcscan/infected-svcscan.txt | grep -i "Binary Path" | sort | uniq > $output_dir/tmpfolder/infected-svcscan.tmp
    diff $output_dir/tmpfolder/baseline-svcscan.tmp $output_dir/tmpfolder/infected-svcscan.tmp | grep -E "^>" | sed 's/^..//' > $output_dir/tmpfolder/diff-svcscan.tmp
    if [[ -s $output_dir/tmpfolder/diff-svcscan.tmp ]] ; then
      echo -e "\n\nNew services." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/diff-svcscan.tmp | sed 's,\\,\\\\\\\\,g' > $output_dir/tmpfolder/loop-svcscan.tmp
      while read line ; do 
        cat $output_dir/svcscan/infected-svcscan.txt | grep -B 9 "`echo $line`" >> $output_dir/tmpfolder/malware-checks.tmp
      done < $output_dir/tmpfolder/loop-svcscan.tmp
    fi

    # find changes in registry keys commonly used for persistence:
    for key in "Microsoft\Windows\CurrentVersion\RunOnce" "Microsoft\Windows\CurrentVersion\Run" "Software\Microsoft\Windows\CurrentVersion\RunOnce" "Software\Microsoft\Windows\CurrentVersion\Run" "Microsoft\Windows\CurrentVersion\RunServices" "Microsoft\Windows\CurrentVersion\RunServicesOnce" "Software\Microsoft\Windows NT\CurrentVersion\Winlogon" "Microsoft\Security Center\Svc" ; do
      vol.py --profile=$profile -f $baseline_memory_image printkey -K $key &> $output_dir/tmpfolder/base.tmp &
      vol.py --profile=$profile -f $infected_memory_image printkey -K $key &> $output_dir/tmpfolder/inf.tmp &
      wait
      tr < $output_dir/tmpfolder/base.tmp -d '\000' > $output_dir/tmpfolder/baseline.tmp
      tr < $output_dir/tmpfolder/inf.tmp -d '\000' > $output_dir/tmpfolder/infected.tmp
      diff $output_dir/tmpfolder/baseline.tmp $output_dir/tmpfolder/infected.tmp | grep -E "^>" | sed 's/^..//' &> $output_dir/tmpfolder/diff.tmp
      if [[ -s $output_dir/tmpfolder/diff.tmp ]] ; then
        echo -e "\n\nRegistry key $key changed." >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
        tail -n +2 $output_dir/tmpfolder/infected.tmp >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    done

    ################################ MALWARE CHECKS - KERNEL ################################

    # find keylogger traces in messagehooks:
    cat $output_dir/messagehooks/diff-messagehooks.txt | grep -i "KEYBOARD" > $output_dir/tmpfolder/keyboard_messagehooks.tmp
    if [[ -s $output_dir/tmpfolder/keyboard_messagehooks.tmp ]]; then
      echo -e "\n\nKeylogger traces (messagehooks)." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/messagehooks/infected-messagehooks.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/messagehooks/infected-messagehooks.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/keyboard_messagehooks.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find unusual new timers:
    cat $output_dir/timers/diff-timers.txt | grep -E -v -i "ataport.SYS|ntoskrnl.exe|NETIO.SYS|storport.sys|afd.sys|cng.sys|dfsc.sys|discache.sys|HTTP.sys|luafv.sys|ndis.sys|Ntfs.sys|rdbss.sys|rdyboost.sys|spsys.sys|srvnet.sys|srv.sys|tcpip.sys|usbccgp.sys" | sort | uniq >> $output_dir/tmpfolder/timers.tmp
    if [[ -s $output_dir/tmpfolder/timers.tmp ]] ; then
      echo -e "\n\nNew timers." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/timers/infected-timers.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/timers/infected-timers.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/timers.tmp >> $output_dir/tmpfolder/malware-checks.tmp
      if [[ $@ =~ "--add-hints" ]] ; then
        echo -e "\nHint: Malware can set kernel timers to run functions at specified intervals." >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    fi

    # find unusual new gditimers:
    cat $output_dir/gditimers/diff-gditimers.txt | grep -E -v -i "dllhost.exe|explorer.exe|csrss.exe" | sort | uniq >> $output_dir/tmpfolder/gditimers.tmp
    if [[ -s $output_dir/tmpfolder/gditimers.tmp ]] ; then
      echo -e "\n\nNew gditimers." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/gditimers/infected-gditimers.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/gditimers/infected-gditimers.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/gditimers.tmp >> $output_dir/tmpfolder/malware-checks.tmp
      if [[ $@ =~ "--add-hints" ]] ; then
        echo -e "\nHint: Malware can set timers to run functions at specified intervals." >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    fi

    # find malicious kernel timers:
    cat $output_dir/timers/diff-timers.txt | grep -i "UNKNOWN" > $output_dir/tmpfolder/unknown_timers.tmp
    if [[ -s $output_dir/tmpfolder/unknown_timers.tmp ]]; then
      echo -e "\n\nNew malicious kernel timers." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/timers/infected-timers.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/timers/infected-timers.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/unknown_timers.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find malicious kernel callbacks:
    cat $output_dir/callbacks/diff-callbacks.txt | grep -i "UNKNOWN" > $output_dir/tmpfolder/unknown_callbacks.tmp
    if [[ -s $output_dir/tmpfolder/unknown_callbacks.tmp ]]; then
      echo -e "\n\nNew malicious kernel callbacks." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/callbacks/infected-callbacks.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/callbacks/infected-callbacks.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/unknown_callbacks.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find unknown drivermodule entries:
    cat $output_dir/drivermodule/diff-drivermodule.txt | grep -i "UNKNOWN" > $output_dir/tmpfolder/unknown_drivermodule.tmp
    if [[ -s $output_dir/tmpfolder/unknown_drivermodule.tmp ]]; then
      echo -e "\n\nNew suspicious drivermodule entries." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/drivermodule/infected-drivermodule.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/drivermodule/infected-drivermodule.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/unknown_drivermodule.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find unknown driverirp entries:
    cat $output_dir/driverirp/diff-driverirp.txt | grep -i "UNKNOWN" > $output_dir/tmpfolder/unknown_driverirp.tmp
    if [[ -s $output_dir/tmpfolder/unknown_driverirp.tmp ]]; then
      echo -e "\n\nNew suspicious driverirp entries." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/unknown_driverirp.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find hooked ssdt functions:
    cat $output_dir/ssdt/diff-ssdt.txt | grep -i -E -v '(ntos|win32k)' | grep -i "Entry" > $output_dir/tmpfolder/hooked_ssdt.tmp
    if [[ -s $output_dir/tmpfolder/hooked_ssdt.tmp ]]; then
      echo -e "\n\nNew hooked ssdt functions." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/hooked_ssdt.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find manipulated idt entries:
    cat $output_dir/idt/diff-idt.txt | grep -i "rsrc" > $output_dir/tmpfolder/manipulated_idt.tmp
    if [[ -s $output_dir/tmpfolder/manipulated_idt.tmp ]]; then
      echo -e "\n\nManipulated idt entries." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/idt/infected-idt.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/idt/infected-idt.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/manipulated_idt.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # display orphan threads:
    cat $output_dir/orphanthreads/diff-orphanthreads.txt > $output_dir/tmpfolder/orphanthreads.tmp
    if [[ -s $output_dir/tmpfolder/orphanthreads.tmp ]]; then
      echo -e "\n\nOrphan threads." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/orphanthreads.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    ################################ MALWARE CHECKS - STRINGS ################################

    echo -e "Hunting for badness in memory strings..."
    # dumping and analysing registry for anomalies
    mkdir $output_dir/dumpregistry
    mkdir $output_dir/tmpfolder/baselineregistry
    mkdir $output_dir/dumpregistry/infectedregistry
    vol.py --profile=$profile -f $baseline_memory_image dumpregistry -D $output_dir/tmpfolder/baselineregistry &> /dev/null &
    vol.py --profile=$profile -f $infected_memory_image dumpregistry -D $output_dir/dumpregistry/infectedregistry &> /dev/null &
    wait
    strings -a -td $output_dir/tmpfolder/baselineregistry/* | sort | uniq > $output_dir/tmpfolder/baseline-registry-strings.txt
    strings -a -td $output_dir/dumpregistry/infectedregistry/* | sort | uniq > $output_dir/tmpfolder/infected-registry-strings.txt
    diff $output_dir/tmpfolder/baseline-registry-strings.txt $output_dir/tmpfolder/infected-registry-strings.txt | grep -E "^>" | sed 's/^..//' &> $output_dir/dumpregistry/diff-registry-strings.txt
    # find ips/domains/emails in new registry strings:
    cat $output_dir/dumpregistry/diff-registry-strings.txt | grep -o -E '\b(https?|ftp|file)://[-A-Za-z0-9+&@#/%?=~_|!:,.;]*[-A-Za-z0-9+&@#/%=~_|]' | uniq >> $output_dir/tmpfolder/diff-reg-ip-domains.tmp
    cat $output_dir/dumpregistry/diff-registry-strings.txt | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | uniq >> $output_dir/tmpfolder/diff-reg-ip-domains.tmp
    cat $output_dir/dumpregistry/diff-registry-strings.txt | grep -E -o "\b[a-zA-Z0-9.-]+@[a-zA-Z0-9.-]+\.[a-zA-Z0-9.-]+\b" | uniq >> $output_dir/tmpfolder/diff-reg-ip-domains.tmp
    if [[ -s $output_dir/tmpfolder/diff-reg-ip-domains.tmp ]] ; then
      echo -e "\n\nNew IPs, domains and email addresses found in registry." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/diff-reg-ip-domains.tmp | sort | uniq >> $output_dir/tmpfolder/malware-checks.tmp
    fi
    # find other suspicious strings in registry:
    for pattern in Web Antivirus Virtualisation Sandbox Sysinternals Shell Keylogger Filepath Password Powershell Infogathering Executable Banking Encryption Socialsites Other ; do
      if [[ $pattern == "Web" ]] ; then regex_str=$web_regex_str ; fi
      if [[ $pattern == "Antivirus" ]] ; then regex_str=$antivirus_regex_str ; fi
      if [[ $pattern == "Virtualisation" ]] ; then regex_str=$virtualisation_regex_str ; fi
      if [[ $pattern == "Sandbox" ]] ; then regex_str=$sandbox_regex_str ; fi
      if [[ $pattern == "Sysinternals" ]] ; then regex_str=$sysinternals_regex_str ; fi
      if [[ $pattern == "Shell" ]] ; then regex_str=$shell_regex_str ; fi
      if [[ $pattern == "Keylogger" ]] ; then regex_str=$keylogger_regex_str ; fi
      if [[ $pattern == "Filepath" ]] ; then regex_str=$filepath_regex_str ; fi
      if [[ $pattern == "Password" ]] ; then regex_str=$password_regex_str ; fi
      if [[ $pattern == "Powershell" ]] ; then regex_str=$powershell_regex_str ; fi
      if [[ $pattern == "Infogathering" ]] ; then regex_str=$infogathering_regex_str ; fi
      if [[ $pattern == "Executable" ]] ; then regex_str=$exec_regex_str ; fi
      if [[ $pattern == "Banking" ]] ; then regex_str=$banking_regex_str ; fi
      if [[ $pattern == "Encryption" ]] ; then regex_str=$crypto_regex_str ; fi
      if [[ $pattern == "Socialsites" ]] ; then regex_str=$socialsites_regex_str ; fi
      if [[ $pattern == "Other" ]] ; then regex_str=$other_regex_str ; fi

      if grep -E -i $regex_str $output_dir/dumpregistry/diff-registry-strings.txt > /dev/null ; then
        echo -e "\n\n$pattern strings found in registry." >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
        grep -E -i $regex_str $output_dir/dumpregistry/diff-registry-strings.txt | sort | uniq >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    done

    # running volatility strings plugin
    mkdir $output_dir/strings
    strings -a -td $output_dir/malfind/dump-dir-infected/* > $output_dir/tmpfolder/process-strings.tmp 2> /dev/null
    strings -a -td $output_dir/procdump/* >> $output_dir/tmpfolder/process-strings.tmp 2> /dev/null
    vol.py --profile=$profile -f $infected_memory_image strings -S --string-file=$output_dir/tmpfolder/process-strings.tmp &> $output_dir/strings/process-strings-vol.txt

    # find ips/domains/emails in strings:
    cat $output_dir/strings/process-strings-vol.txt | grep -E '\b(https?|ftp|file)://[-A-Za-z0-9+&@#/%?=~_|!:,.;]*[-A-Za-z0-9+&@#/%=~_|]' | uniq >> $output_dir/tmpfolder/infected-ip-domains.tmp
    cat $output_dir/strings/process-strings-vol.txt | grep -E "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | uniq >> $output_dir/tmpfolder/infected-ip-domains.tmp
    cat $output_dir/strings/process-strings-vol.txt | grep -E "\b[a-zA-Z0-9.-]+@[a-zA-Z0-9.-]+\.[a-zA-Z0-9.-]+\b" | uniq >> $output_dir/tmpfolder/infected-ip-domains.tmp
    if [[ -s $output_dir/tmpfolder/infected-ip-domains.tmp ]] ; then
      echo -e "\n\nNew IPs, domains and email addresses found in memory strings." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/infected-ip-domains.tmp | sort | uniq >> $output_dir/tmpfolder/malware-checks.tmp
    fi
    
    # find other suspicious strings in memory:
    for pattern in Web Antivirus Virtualisation Sandbox Sysinternals Shell Keylogger Filepath Password Powershell Infogathering Executable Banking Encryption Socialsites Other ; do
      if [[ $pattern == "Web" ]] ; then regex_str=$web_regex_str ; fi
      if [[ $pattern == "Antivirus" ]] ; then regex_str=$antivirus_regex_str ; fi
      if [[ $pattern == "Virtualisation" ]] ; then regex_str=$virtualisation_regex_str ; fi
      if [[ $pattern == "Sandbox" ]] ; then regex_str=$sandbox_regex_str ; fi
      if [[ $pattern == "Sysinternals" ]] ; then regex_str=$sysinternals_regex_str ; fi
      if [[ $pattern == "Shell" ]] ; then regex_str=$shell_regex_str ; fi
      if [[ $pattern == "Keylogger" ]] ; then regex_str=$keylogger_regex_str ; fi
      if [[ $pattern == "Filepath" ]] ; then regex_str=$filepath_regex_str ; fi
      if [[ $pattern == "Password" ]] ; then regex_str=$password_regex_str ; fi
      if [[ $pattern == "Powershell" ]] ; then regex_str=$powershell_regex_str ; fi
      if [[ $pattern == "Infogathering" ]] ; then regex_str=$infogathering_regex_str ; fi
      if [[ $pattern == "Executable" ]] ; then regex_str=$exec_regex_str ; fi
      if [[ $pattern == "Banking" ]] ; then regex_str=$banking_regex_str ; fi
      if [[ $pattern == "Encryption" ]] ; then regex_str=$crypto_regex_str ; fi
      if [[ $pattern == "Socialsites" ]] ; then regex_str=$socialsites_regex_str ; fi
      if [[ $pattern == "Other" ]] ; then regex_str=$other_regex_str ; fi

      if grep -E -i $regex_str $output_dir/strings/process-strings-vol.txt > /dev/null ; then
        echo -e "\n\n$pattern strings found in memory." >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
        grep -E -i $regex_str $output_dir/strings/process-strings-vol.txt | sort | uniq >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    done

    ################################ MALWARE CHECKS - IMPORTS ################################

    # analyse import tables in new processes:
    plugin=impscan
    tail -n +4 $output_dir/psscan/diff-psscan.txt | tr -s ' ' | cut -d " " -f 3 | sort | uniq > $output_dir/tmpfolder/procids.tmp
    cat $output_dir/malfind/diff-malfind.txt | grep "Address:" | cut -d ' ' -f 4 | sort | uniq >> $output_dir/tmpfolder/procids.tmp
    cat $output_dir/tmpfolder/procids.tmp | sort | uniq > $output_dir/tmpfolder/pids.tmp
    while read pid; do
      vol.py --profile=$profile -f $memory_image $plugin -p $pid &> $output_dir/tmpfolder/$pid-imports.tmp
      process=`tail -n +4 $output_dir/psscan/infected-psscan.txt | tr -s ' ' | cut -d ' ' -f 1-3 | grep -i " "$pid | cut -d ' ' -f 2 | sort | uniq`
      # searching for anti debug import functions
      cat $output_dir/tmpfolder/$pid-imports.tmp | grep -i -E $anti_debug_imports > $output_dir/tmpfolder/$pid-imports-susp.tmp
      # search for password extraction import functions 
      cat $output_dir/tmpfolder/$pid-imports.tmp | grep -i -E $password_extract_imports >> $output_dir/tmpfolder/$pid-imports-susp.tmp
      # searching for web request import functions
      cat $output_dir/tmpfolder/$pid-imports.tmp | grep -i -E $web_imports >> $output_dir/tmpfolder/$pid-imports-susp.tmp
      # searching for service import functions
      cat $output_dir/tmpfolder/$pid-imports.tmp | grep -i -E $service_imports >> $output_dir/tmpfolder/$pid-imports-susp.tmp
      # searching for process injection import functions
      cat $output_dir/tmpfolder/$pid-imports.tmp | grep -i -E $process_injection_imports >> $output_dir/tmpfolder/$pid-imports-susp.tmp
      # searching for uac bypass import functions
      cat $output_dir/tmpfolder/$pid-imports.tmp | grep -i -E $uac_bypass_imports >> $output_dir/tmpfolder/$pid-imports-susp.tmp
      # searching for misc import functions
      cat $output_dir/tmpfolder/$pid-imports.tmp | grep -i -E $misc_imports >> $output_dir/tmpfolder/$pid-imports-susp.tmp
      if [[ -s $output_dir/tmpfolder/$pid-imports-susp.tmp ]] ; then
        echo -e "\n\nSuspicious imports in process $process." >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
        sed -n '2p' $output_dir/tmpfolder/$pid-imports.tmp >> $output_dir/tmpfolder/malware-checks.tmp
        sed -n '3p' $output_dir/tmpfolder/$pid-imports.tmp >> $output_dir/tmpfolder/malware-checks.tmp
        cat $output_dir/tmpfolder/$pid-imports-susp.tmp >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    done < $output_dir/tmpfolder/pids.tmp

  fi

  ################################ REPORT CREATION ################################
  if [[ $@ =~ "--no-report" ]] ; then
    endtime=$(date +%s)
    echo -e "\nAll done in $(($endtime - $starttime)) seconds."
    rm -r $output_dir/tmpfolder &> /dev/null
    notify-send "VolDiff execution completed."
    exit
  fi
  echo -e "Creating a report..."
  report=VolDiff-report.txt
  touch $output_dir/$report
  echo -e " _    __      ______  _ ________" >> $output_dir/$report
  echo -e "| |  / /___  / / __ \(_) __/ __/" >> $output_dir/$report
  echo -e "| | / / __ \/ / / / / / /_/ /_  " >> $output_dir/$report
  echo -e "| |/ / /_/ / / /_/ / / __/ __/  " >> $output_dir/$report
  echo -e "|___/\____/_/_____/_/_/ /_/     " >> $output_dir/$report
  echo -e "\nVolatility analysis report generated by VolDiff v$version." >> $output_dir/$report 
  echo -e "Download the latest VolDiff version from https://github.com/aim4r/VolDiff/.\n" >> $output_dir/$report
  echo -e "Baseline memory image: $baseline_memory_image" >> $output_dir/$report 
  echo -e "Infected memory image: $infected_memory_image" >> $output_dir/$report 
  echo -e "Profile: $profile" >> $output_dir/$report 
  touch $output_dir/tmpfolder/no_new_entries.tmp
  for plugin in "${plugins_to_report[@]}"
  do
    if [[ -s $output_dir/$plugin/diff-$plugin.txt ]] ; then  
      # processing pslist and psscan output:
      if [[ $plugin = "pslist"  ]] || [[ $plugin = "psscan"  ]] ; then
       echo -e "\n\nNew $plugin entries." >> $output_dir/$report
       echo -e "===========================================================================\n" >> $output_dir/$report
       sed -n '2p' $output_dir/$plugin/infected-$plugin.txt >> $output_dir/$report
       sed -n '3p' $output_dir/$plugin/infected-$plugin.txt >> $output_dir/$report
       cat $output_dir/$plugin/baseline-$plugin.txt | tr -s ' ' | cut -d " " -f 3 > $output_dir/tmpfolder/baseline-pids.tmp
       cat $output_dir/$plugin/infected-$plugin.txt | tr -s ' ' | cut -d " " -f 3  > $output_dir/tmpfolder/infected-pids.tmp
       diff $output_dir/tmpfolder/baseline-pids.tmp $output_dir/tmpfolder/infected-pids.tmp | grep -E "^>" | sed 's/^..//' | uniq &>> $output_dir/tmpfolder/unique-new-pids.tmp
       while read pid; do
         cat $output_dir/$plugin/infected-$plugin.txt | grep -E "[a-zA-Z] +$pid " >> $output_dir/$report
       done < $output_dir/tmpfolder/unique-new-pids.tmp

      #processing netscan output
      elif [[ $plugin = "netscan"  ]] ; then
        echo -e "\n\nNew $plugin entries." >> $output_dir/$report
        echo -e "===========================================================================\n" >> $output_dir/$report
        sed -n '2p' $output_dir/$plugin/infected-$plugin.txt >> $output_dir/$report
        cat $output_dir/$plugin/diff-$plugin.txt >> $output_dir/$report
      #filtering mutantscan output
      elif [[ $plugin = "mutantscan"  ]] ; then
        echo -e "\n\nNew $plugin entries." >> $output_dir/$report
        echo -e "===========================================================================" >> $output_dir/$report
        cat $output_dir/$plugin/diff-$plugin.txt | tr -s ' ' | cut -d ' ' -f 6 | sort | uniq >> $output_dir/$report
        if [[ $@ =~ "--add-hints" ]] ; then
          echo -e "\nHint: Google mutants associated with suspicious processes." >> $output_dir/$report
        fi

      # processing plugins that don't need output formatting:
      elif [[ $plugin = "devicetree" ]] || [[ $plugin = "orphanthreads" ]] || [[ $plugin = "cmdline" ]] || [[ $plugin = "consoles" ]] || [[ $plugin = "svcscan" ]] || [[ $plugin = "driverirp" ]] || [[ $plugin = "malfind" ]] || [[ $plugin = "shellbags" ]] || [[ $plugin = "iehistory" ]] || [[ $plugin = "sessions" ]] || [[ $plugin = "eventhooks" ]] ; then
        echo -e "\n\nNew $plugin entries." >> $output_dir/$report
        echo -e "===========================================================================\n" >> $output_dir/$report
        cat $output_dir/$plugin/diff-$plugin.txt >> $output_dir/$report

      # processing other plugins:
      else
        echo -e "\n\nNew $plugin entries." >> $output_dir/$report
        echo -e "===========================================================================\n" >> $output_dir/$report
        sed -n '2p' $output_dir/$plugin/infected-$plugin.txt >> $output_dir/$report
        sed -n '3p' $output_dir/$plugin/infected-$plugin.txt >> $output_dir/$report
        cat $output_dir/$plugin/diff-$plugin.txt >> $output_dir/$report
      fi
      # adding hints to help in further analysis:
      if [[ $@ =~ "--add-hints" ]] ; then
        if [[ $plugin = "malfind" ]] ; then
          echo -e "\nHint: Suspicious malfind processes were dumped to disk, and can be reversed as normal or uploaded to VirusTotal." >> $output_dir/$report
        fi
        if [[ $plugin = "drivermodule" ]] ; then
          echo -e "\nHint: Use moddump -b to dump suspicious drivers from memory to disk." >> $output_dir/$report
        fi
        if [[ $plugin = "driverscan" ]] ; then
          echo -e "\nHint: Drivers that have no associated service should be considered as suspicious. Use moddump -b to dump suspicious drivers from memory to disk." >> $output_dir/$report
        fi
        if [[ $plugin = "psxview" ]] ; then
          echo -e "\nHint: Use procexedump to dump suspcious processes from memory to disk." >> $output_dir/$report
        fi
        if [[ $plugin = "netscan" ]] ; then
          echo -e "\nHint: Translate suspicious IPs to domains using Google/VirusTotal, and search for the associated domains in memory strings." >> $output_dir/$report
        fi
        if [[ $plugin = "ssdt" ]] ; then
          echo -e "\nHint: Some rootkits manipulate SSDT entries to hide its files or registry entries from usermode." >> $output_dir/$report
        fi
        if [[ $plugin = "iehistory" ]] ; then
          echo -e "\nHint: iehistory can reveal history details of malware that uses the WinINet API." >> $output_dir/$report
        fi
        if [[ $plugin = "envars" ]] ; then
          echo -e "\nHint: Some malware will change the PATH and PATHEXT environment variables." >> $output_dir/$report
        fi
        if [[ $plugin = "messagehooks" ]] ; then
          echo -e "\nHint: messagehooks can detect hooks that attempt to catch user strokes." >> $output_dir/$report
        fi
      fi
    else
      echo -e "$plugin" >> $output_dir/tmpfolder/no_new_entries.tmp 
    fi
  done

  # display list of plugins with no notable changes:
  if [[ -s $output_dir/tmpfolder/no_new_entries.tmp ]]; then
    echo -e "\n\nNo notable changes to highlight from the following plugins." >> $output_dir/$report
    echo -e "===========================================================================\n" >> $output_dir/$report
    cat $output_dir/tmpfolder/no_new_entries.tmp >> $output_dir/$report
  fi

  # display list of plugins hidden from report (verbose):
  echo -e "\n\nPlugins that were executed but are not included in the report above." >> $output_dir/$report
  echo -e "===========================================================================\n" >> $output_dir/$report
  echo -e "filescan\nhandles\ngetsids\ndeskscan\ndlllist\nldrmodules\natoms\nsvcscan\natomscan\nidt\ngdt\ntimers\ngditimers" >> $output_dir/$report

  # add identified process anomalies to the report:
  if [[ $@ =~ "--malware-checks" ]] ; then
    if [[ -s $output_dir/tmpfolder/malware-checks.tmp ]]; then
      echo -e "" >> $output_dir/$report
      echo "   _               _           _         __                 _ _       " >> $output_dir/$report
      echo "  /_\  _ __   __ _| |_   _ ___(_)___    /__\ ___  ___ _   _| | |_ ___ " >> $output_dir/$report
      echo -E " //_\\\\| '_ \\ / _\` | | | | / __| / __|  / \\/// _ \\/ __| | | | | __/ __|" >> $output_dir/$report
      echo -E "/  _  \\ | | | (_| | | |_| \\__ \\ \\__ \\ / _  \\  __/\\__ \\ |_| | | |_\\__ \\" >> $output_dir/$report
      echo "\_/ \_/_| |_|\__,_|_|\__, |___/_|___/ \/ \_/\___||___/\__,_|_|\__|___/" >> $output_dir/$report
      echo "                     |___/                                            " >> $output_dir/$report
      cat $output_dir/tmpfolder/malware-checks.tmp >> $output_dir/$report
    fi
  fi

  echo -e "\n\nEnd of report." >> $output_dir/$report
  rm -r $output_dir/tmpfolder &> /dev/null

  endtime=$(date +%s)
  echo -e "\nAll done in $(($endtime - $starttime)) seconds, report saved to $output_dir/$report."
  notify-send "VolDiff execution completed."

################################################################## ENTER STANDALONE MODE ################################################################## 

elif [[ $mode = "standalone" ]] ; then
  echo -e "Only one memory image specified: enter standalone mode..."
  ################################ SETTING PROFILE AND FINDING PATH TO MEMORY IMAGES ################################
  if [[ -f $1 ]] ; then
    memory_image=$1
    echo -e "Path to memory image: $memory_image..."
  elif [[ -f infected.raw ]] ; then
    memory_image=infected.raw
    echo -e "Path to memory image is not valid or was not specified. Using default ($memory_image)..."
  elif [[ -f infected.vmem ]] ; then
    memory_image=infected.vmem
    echo -e "Path to memory image is not valid or was not specified. Using default ($memory_image)..."
  else
    echo -e "Please specify a path to a memory image."
    exit
  fi
  if [[ -z $2 ]] ; then
    profile=Win7SP0x86
    echo -e "Profile is not specified. Using default ($profile)..."
  elif [[ $2 != Win7SP1x64 ]] &&  [[ $2 != Win7SP0x86 ]] &&  [[ $2 != Win7SP0x64 ]] &&  [[ $2 != Win7SP1x86 ]] ;  then
    profile=$2
    echo -e "WARNING: This script was only tested using Windows 7 profiles. The specified profile ($profile) seems different!" 
  else
    profile=$2
    echo -e "Profile: $profile..."
  fi

  ################################ CREATING FOLDER TO STORE OUTPUT ################################
  starttime=$(date +%s)
  output_dir=VolDiff_$(date +%F_%R)
  mkdir $output_dir
  mkdir $output_dir/tmpfolder

  ################################ RUNNING VOLATILITY PLUGINS ################################
  echo -e "Running a selection of volatility plugins (time consuming)..."
  for plugin in "${plugins_to_run[@]}" 
  do
    echo -e "Volatility plugin "$plugin" execution in progress..."
    mkdir $output_dir/$plugin
    if [[ $plugin = "mutantscan" ]] || [[ $plugin = "handles" ]] || [[ $plugin = "privs" ]]  || [[ $plugin = "envars" ]] ; then
      vol.py --profile=$profile -f $memory_image $plugin --silent &> $output_dir/$plugin/$plugin.txt
    elif [[ $plugin = "orphanthreads" ]]  ; then
      vol.py --profile=$profile -f $memory_image threads -F OrphanThread &> $output_dir/orphanthreads/orphanthreads.txt
    elif [[ $plugin = "psxview" ]]  ; then
      vol.py --profile=$profile -f $memory_image psxview -R &> $output_dir/psxview/psxview.txt
    elif [[ $plugin = "malfind" ]] ; then
      mkdir $output_dir/$plugin/dump-dir
      vol.py --profile=$profile -f $memory_image $plugin -D $output_dir/$plugin/dump-dir &> $output_dir/$plugin/$plugin.txt
    else
      vol.py --profile=$profile -f $memory_image $plugin &> $output_dir/$plugin/$plugin.txt
    fi
  done
  wait

  if [[ $@ =~ "--malware-checks" ]] ; then
    echo -e "Hunting for anomalies in $memory_image processes..."
    touch $output_dir/tmpfolder/malware-checks.tmp

    ################################ MALWARE CHECKS - NETWORK ################################

    # compute unique IPs from netscan output:
    cat $output_dir/netscan/netscan.txt | grep -o -E "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | sort | uniq | grep -v -E "127\.0\.0\.1|0\.0\.0\.0" > $output_dir/tmpfolder/netscan-uniq-ips.tmp
    if [[ -s $output_dir/tmpfolder/netscan-uniq-ips.tmp ]]; then
      echo -e "\n\nUnique IP addresses from netscan output." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/netscan-uniq-ips.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    ################################ MALWARE CHECKS - PROCESS CHECKS ################################
   
    # verify PID of System process = 4
    cat $output_dir/psscan/psscan.txt | grep " System " | tr -s ' ' | cut -d " " -f 3 > $output_dir/tmpfolder/system-pids.tmp
    while read pid; do
      if [[ $pid != "4" ]] ; then
        echo -e "\nSuspicious 'System' process running with PID $pid (expected PID 4)." >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    done < $output_dir/tmpfolder/system-pids.tmp

   # verify that only one instance of certain processes is running:
    for process in " services.exe" " System" " wininit.exe" " smss.exe" " lsass.exe" " lsm.exe" " explorer.exe"; do
      if [[ "$(cat $output_dir/psscan/psscan.txt | grep $process | wc -l)" != "1" ]] ; then
        echo -e "\n\nMultiple instances of$process were detected." >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
        sed -n '2p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
        sed -n '3p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
        cat $output_dir/psscan/psscan.txt | grep $process >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    done

    # verify that some processes do not have a child:
    for process in "lsass.exe" "lsm.exe"; do
      cat $output_dir/psscan/psscan.txt | grep $process | tr -s ' ' | cut -d " " -f 3 >> $output_dir/tmpfolder/cpids.tmp
    done
    cat $output_dir/psscan/psscan.txt | tr -s ' ' | cut -d " " -f 4 >> $output_dir/tmpfolder/ppids.tmp
    while read pid; do
      while read ppid; do
        if [[ "$pid" == "$ppid" ]]; then
          echo -e "\n\nProcess with (PID $ppid) is not supposed to be a parent." >> $output_dir/tmpfolder/malware-checks.tmp
          echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
          sed -n '2p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
          sed -n '3p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
          cat $output_dir/psscan/psscan.txt | grep " $ppid " >> $output_dir/tmpfolder/malware-checks.tmp
        fi
      done < $output_dir/tmpfolder/ppids.tmp
    done < $output_dir/tmpfolder/cpids.tmp

    # verify child/parent process relationships:
    for child in " svchost.exe" " smss.exe" " conhost.exe" " audiodg.exe" " services.exe" " lsass.exe" " lsm.exe" " taskhost.exe" " spoolsv.exe" " sppsvc.exe" " taskhost.exe" " mscorsvw.exe" " TPAutoConnSvc" " SearchIndexer" " WmiPrvSE.exe" ; do
      if [[ $child = " sppsvc.exe" ]] || [[ $child = " taskhost.exe" ]] || [[ $child = " mscorsvw.exe" ]] || [[ $child = " TPAutoConnSvc" ]] || [[ $child = " SearchIndexer" ]] || [[ $child = " svchost.exe" ]] || [[ $child = " taskhost.exe" ]] || [[ $child = " spoolsv.exe" ]] ; then parent=" services.exe" ; fi
      if [[ $child = " smss.exe" ]] ; then parent=" System" ; fi
      if [[ $child = " WmiPrvSE.exe" ]] || [[ $child = " audiodg.exe" ]]  ; then parent=" svchost.exe"; fi
      if [[ $child = " conhost.exe" ]] ; then parent=" csrss.exe" ; fi
      if [[ $child = " services.exe" ]] || [[ $child = " lsass.exe" ]] || [[ $child = " lsm.exe" ]] ; then parent=" wininit.exe" ; fi

      if grep $child $output_dir/psscan/psscan.txt > /dev/null ; then
        if [[ "$(cat $output_dir/psscan/psscan.txt | grep $parent | wc -l)" = "1" ]] ; then
          cat $output_dir/psscan/psscan.txt | grep $child | tr -s ' ' | cut -d " " -f 4 > $output_dir/tmpfolder/child-ppids.tmp
          parent_pid="$(cat $output_dir/psscan/psscan.txt | grep $parent | tr -s ' ' | cut -d ' ' -f 3)"
          while read ppid; do
            ppid=$( printf $ppid )
            parent_pid=$( printf $parent_pid )
            if [[ $ppid != $parent_pid ]] ; then
              tail -n +4 $output_dir/psscan/psscan.txt | tr -s ' ' | cut -d ' ' -f 2-3 | grep -i " "$ppid | cut -d ' ' -f 1 | sort | uniq > $output_dir/tmpfolder/ppidprocess.tmp
              if [[ -s $output_dir/tmpfolder/ppidprocess.tmp ]] ; then   
                ppidlines=`cat $output_dir/tmpfolder/ppidprocess.tmp | wc -l`  &> /dev/null
                if [[ $ppidlines = 1 ]] ; then
                  echo -e "\n\nUnexpected parent process for$child: PPID $ppid (`cat $output_dir/tmpfolder/ppidprocess.tmp`) instead of PPID $parent_pid ($parent )." >> $output_dir/tmpfolder/malware-checks.tmp
                  echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
                  sed -n '2p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
                  sed -n '3p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
                  cat $output_dir/psscan/psscan.txt | grep " $ppid " >> $output_dir/tmpfolder/malware-checks.tmp
                else
                  cat $output_dir/tmpfolder/ppidprocess.tmp | tr '\n' ' ' > $output_dir/tmpfolder/ppparents.tmp
                  echo -e "\n\nUnexpected parent process for$child: PPID $ppid ( multiple associated processes: `cat $output_dir/tmpfolder/ppparents.tmp`) instead of PPID $parent_pid ($parent )." >> $output_dir/tmpfolder/malware-checks.tmp
                  echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
                  sed -n '2p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
                  sed -n '3p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
                  cat $output_dir/psscan/psscan.txt | grep " $ppid " >> $output_dir/tmpfolder/malware-checks.tmp
                fi
              else
                echo -e "\n\nUnexpected parent process for$child: PPID $ppid (could not map associated process name) instead of PPID $parent_pid ($parent )." >> $output_dir/tmpfolder/malware-checks.tmp
                echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
                sed -n '2p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
                sed -n '3p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
                cat $output_dir/psscan/psscan.txt | grep " $ppid " >> $output_dir/tmpfolder/malware-checks.tmp
              fi
            fi     
          done < $output_dir/tmpfolder/child-ppids.tmp
        fi
      fi

    done

    # verify that every process has a parent (except for explorer.exe, csrss.exe, wininit.exe and winlogon.exe):
    mkdir $output_dir/tmpfolder/ppids
    tail -n +4 $output_dir/psscan/psscan.txt | tr -s ' ' | cut -d ' ' -f 4 | sort | uniq | grep -v "^0$" > $output_dir/tmpfolder/ppids/ppids.temp
    tail -n +4 $output_dir/psscan/psscan.txt | tr -s ' ' | cut -d ' ' -f 3 | sort | uniq > $output_dir/tmpfolder/ppids/pids.temp
    while read ppid; do 
      if ! grep -E "^$ppid$" $output_dir/tmpfolder/ppids/pids.temp > /dev/null ; then
        tail -n +4 $output_dir/psscan/psscan.txt | tr -s ' ' | cut -d ' ' -f 2,3,4 | grep -E " $ppid$" | cut -d ' ' -f 1 | sort | uniq > $output_dir/tmpfolder/ppids/processes-$ppid.temp
        cat $output_dir/tmpfolder/ppids/processes-$ppid.temp | tr '\n' ' ' > $output_dir/tmpfolder/ppids/processes-$ppid-space.temp
        if  ! grep -E -i "explorer.exe|csrss.exe|wininit.exe|winlogon.exe" $output_dir/tmpfolder/ppids/processes-$ppid-space.temp > /dev/null ; then 
          echo -e "\n\nPPID $ppid does not have an associated process." >> $output_dir/tmpfolder/malware-checks.tmp
          echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
          sed -n '2p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
          sed -n '3p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
          cat $output_dir/psscan/psscan.txt | grep " $ppid " >> $output_dir/tmpfolder/malware-checks.tmp
        fi 
      fi  
    done < $output_dir/tmpfolder/ppids/ppids.temp

    # verify processes are running in expected sessions:
    for process in " wininit.exe" " services.exe" " lsass.exe" " svchost.exe" " lsm.exe" " winlogon.exe" ; do
      if [[ $process = " csrss.exe" ]] || [[ $process = " wininit.exe" ]] || [[ $process = " services.exe" ]] || [[ $process = " lsass.exe" ]] || [[ $process = " svchost.exe" ]]|| [[ $process = " lsm.exe" ]]; then session="0"; fi
      if [[ $process = " winlogon.exe" ]] ; then session="1" ; fi
      cat $output_dir/pslist/pslist.txt | grep $process | tr -s ' ' | cut -d ' ' -f 7 > $output_dir/tmpfolder/process_sessions.tmp
      while read psession; do
        if [[ $psession != $session ]] ; then
          echo -e "\n\nProcess$process running in unexpected session ($psession instead of $session)." >> $output_dir/tmpfolder/malware-checks.tmp
          echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
          sed -n '2p' $output_dir/pslist/pslist.txt >> $output_dir/tmpfolder/malware-checks.tmp
          sed -n '3p' $output_dir/pslist/pslist.txt >> $output_dir/tmpfolder/malware-checks.tmp
          cat $output_dir/pslist/pslist.txt | grep $process >> $output_dir/tmpfolder/malware-checks.tmp
        fi
      done < $output_dir/tmpfolder/process_sessions.tmp
    done

    # check process executable path:
    for process in "smss.exe" "crss.exe" "wininit.exe" "services.exe" "lsass.exe" "svchost.exe" "lsm.exe" "explorer.exe" "winlogon"; do
      if [[ $process == "smss.exe" ]]; then processpath="\systemroot\system32\smss.exe" ; fi
      if [[ $process == "crss.exe" ]]; then processpath="\windows\system32\csrss.exe" ; fi
      if [[ $process == "wininit.exe" ]]; then processpath="\windows\system32\wininit.exe" ; fi
      if [[ $process == "services.exe" ]]; then processpath="\windows\system32\services.exe" ; fi
      if [[ $process == "lsass.exe" ]]; then processpath="\windows\system32\lsass.exe" ; fi
      if [[ $process == "svchost.exe" ]]; then processpath="\windows\system32\svchost.exe" ; fi
      if [[ $process == "lsm.exe" ]]; then processpath="\windows\system32\lsm.exe" ; fi
      if [[ $process == "explorer.exe" ]]; then processpath="\windows\explorer.exe" ; fi
      if [[ $process == "winlogon.exe" ]]; then processpath="\windows\system32\winlogon.exe" ; fi
      if [[ $process == "sppsvc.exe" ]]; then processpath="\windows\system32\sppsvc.exe" ; fi
      cat $output_dir/dlllist/dlllist.txt | grep -i -A 1 $process | grep "Command line" | grep -o '\\.*' | cut -d ' ' -f 1 | tr '[:upper:]' '[:lower:]' | sed 's,\\,\\\\,g' > $output_dir/tmpfolder/path_list.tmp
      if [[ -s $output_dir/tmpfolder/path_list.tmp ]]; then
        while read path; do
          if [[ "$path" != "$processpath" ]]; then
            echo -e "\n\nProcess running from an unexpected path." >> $output_dir/tmpfolder/malware-checks.tmp
            echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
            echo -e "Process $process is running from $path instead of $processpath" >> $output_dir/tmpfolder/malware-checks.tmp
          fi
        done < $output_dir/tmpfolder/path_list.tmp
      fi
    done

    # verify if any processes have suspicious l33t names:
    cat $output_dir/psscan/psscan.txt | grep -E -i $l33t_process_name > $output_dir/tmpfolder/suspicious_process.tmp
    if [[ -s $output_dir/tmpfolder/suspicious_process.tmp ]]; then
      echo -e "\n\nProcess with suspicious name." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/suspicious_process.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # verify if any hacker tools were used in process list:
    cat $output_dir/psscan/psscan.txt | grep -E -i $hacker_process_regex > $output_dir/tmpfolder/suspicious_tools.tmp
    if [[ -s $output_dir/tmpfolder/suspicious_tools.tmp ]]; then
      echo -e "\n\nProcesses that may have been used for lateral movement, exfiltration etc." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/psscan/psscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/suspicious_tools.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # detect process hollowing:
    mkdir $output_dir/tmpfolder/hollowing
    vol.py --profile=$profile -f $memory_image procdump -u -D $output_dir/tmpfolder/hollowing/ &> /dev/null
    cat $output_dir/psscan/psscan.txt | tr -s ' ' | cut -d ' ' -f 2 | cut -d '.' -f 1 | sort | uniq > $output_dir/tmpfolder/process-names.tmp
    tail -n +4 $output_dir/tmpfolder/process-names.tmp > $output_dir/tmpfolder/procnames.tmp
    while read process ; do
      cat $output_dir/psscan/psscan.txt | grep -i $process | tr -s ' ' | cut -d ' ' -f 3 > $output_dir/tmpfolder/$process-pids.tmp
      touch $output_dir/tmpfolder/$process-size.tmp
      while read pid ; do
        ls -l $output_dir/tmpfolder/hollowing/ | tr -s ' ' | cut -d ' ' -f5,9 | grep -i "executable.$pid.exe" | cut -d ' ' -f 1 >> $output_dir/tmpfolder/$process-size.tmp
      done < $output_dir/tmpfolder/$process-pids.tmp
      cat $output_dir/tmpfolder/$process-size.tmp | uniq > $output_dir/tmpfolder/$process-size-uniq.tmp
      lines=`wc -l < $output_dir/tmpfolder/$process-size-uniq.tmp`
      if [[ $lines != 1 ]] && [[ $lines != 0 ]]  ; then 
        echo -e "\n\nPotential process hollowing detected in $process (based on size)." >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "Process    PID  Size" >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "-----------------------------------" >> $output_dir/tmpfolder/malware-checks.tmp
        while read pid ; do
          echo -e "$process    $pid  `ls -l $output_dir/tmpfolder/hollowing/ | tr -s ' ' | cut -d ' ' -f5,9 | grep -i "executable.$pid.exe" | cut -d ' ' -f 1`" >> $output_dir/tmpfolder/malware-checks.tmp
        done < $output_dir/tmpfolder/$process-pids.tmp   
      fi
    done < $output_dir/tmpfolder/procnames.tmp

    # detect processes with exit time but active threads:
    cat $output_dir/psxview/psxview.txt | tr -s ' ' | cut -d ' ' -f 1,2,6,13 | grep "UTC" | grep "True" | cut -d ' ' -f 1 > $output_dir/tmpfolder/exit_with_threads.tmp
    if [[ -s $output_dir/tmpfolder/exit_with_threads.tmp ]]; then
      echo -e "\n\nProcess(es) with exit time and active threads running." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/psxview/psxview.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/psxview/psxview.txt >> $output_dir/tmpfolder/malware-checks.tmp
      while read procname ; do 
        cat $output_dir/psxview/psxview.txt | grep $procname >> $output_dir/tmpfolder/malware-checks.tmp
      done < $output_dir/tmpfolder/exit_with_threads.tmp
    fi

    # check if any proces has domain or enterprise admin privileges:
    cat $output_dir/getsids/getsids.txt | egrep '(Domain Admin|Enterprise Admin|Schema Admin)' > $output_dir/tmpfolder/suspicious_privlege.tmp
    if [[ -s $output_dir/tmpfolder/suspicious_privlege.tmp ]]; then
      echo -e "\n\nProcess(es) with domain or enterprise admin privileges." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/suspicious_privlege.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # check if any process has debug privileges:
    cat $output_dir/privs/privs.txt | grep -i "debug" > $output_dir/tmpfolder/debug_privs.tmp
    if [[ -s $output_dir/tmpfolder/debug_privs.tmp ]]; then
      echo -e "\n\nProcess(es) with debug privileges." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/privs/privs.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/privs/privs.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/debug_privs.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # check if any process has a raw socket handle:
    cat $output_dir/handles/handles.txt | grep -F "\Device\RawIp" > $output_dir/tmpfolder/raw_socket.tmp
    if [[ -s $output_dir/tmpfolder/raw_socket.tmp ]]; then
      echo -e "\n\nRaw socket handles." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/handles/handles.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/handles/handles.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/raw_socket.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # check if any process has a handle to a remote mapped share:
    cat $output_dir/handles/handles.txt | grep -F "\\\\Device\\\\(LanmanRedirector|Mup)" > $output_dir/tmpfolder/remote_shares.tmp
    if [[ -s $output_dir/tmpfolder/remote_shares.tmp ]]; then
      echo -e "\n\nRemote share handles." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/handles/handles.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/handles/handles.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/remote_shares.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    ################################ MALWARE CHECKS - DLLs ################################

    # find new dlls (atoms):
    cat $output_dir/atoms/atoms.txt | grep -i -E ".dll$"  >> $output_dir/tmpfolder/atoms.tmp
    if [[ -s $output_dir/tmpfolder/atoms.tmp ]] ; then
      echo -e "\n\nDLLs found in atoms output." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/atoms/atoms.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/atoms/atoms.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/atoms.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find new dlls (atomscan):
    cat $output_dir/atomscan/atomscan.txt | grep -i -E ".dll$"  >> $output_dir/tmpfolder/atomscan.tmp
    if [[ -s $output_dir/tmpfolder/atomscan.tmp ]] ; then
      echo -e "\n\nDLLs found in atomscan output." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/atomscan/atomscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/atomscan/atomscan.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/atomscan.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # highlight hidden DLLs (ldrmodules):
    cat $output_dir/ldrmodules/ldrmodules.txt | grep "False" | grep -E -v -i "system32|explorer.exe|iexplore.exe|.fon$" | sort | uniq > $output_dir/tmpfolder/ldrmodules.tmp
    if [[ -s $output_dir/tmpfolder/ldrmodules.tmp ]] ; then
      echo -e "\n\nSuspicious ldrmodules entries." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/ldrmodules/ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/ldrmodules/ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/ldrmodules.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi
    # find highly suspicious DLLs used for password stealing (ldrmodules):
    cat $output_dir/ldrmodules/ldrmodules.txt | grep -E -i $hacker_dll_regex | sort | uniq > $output_dir/tmpfolder/ldrmodule_hacker.tmp
    if [[ -s $output_dir/tmpfolder/ldrmodule_hacker.tmp ]] ; then
      echo -e "\n\nDLLs that may have been used for password theft." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/ldrmodules/ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/ldrmodules/ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/ldrmodule_hacker.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find DLLs with no path / no name (indicates process hollowing) (ldrmodules):
    cat $output_dir/ldrmodules/ldrmodules.txt | grep -E -i "no name" | sort | uniq > $output_dir/tmpfolder/ldrmodule_hollow.tmp
    if [[ -s $output_dir/tmpfolder/ldrmodule_hollow.tmp ]] ; then
      echo -e "\n\nDLLs with no path/name (indicates process hollowing)." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/ldrmodules/ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/ldrmodules/ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/ldrmodule_hollow.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    ################################ MALWARE CHECKS - FILES ################################

    # find DLLs/EXES loaded from temp folders (dlllist):
    cat $output_dir/dlllist/dlllist.txt | grep -E -i "TMP|TEMP|AppData" | sort | uniq > $output_dir/tmpfolder/dlllist_temp.tmp
    if [[ -s $output_dir/tmpfolder/dlllist_temp.tmp ]] ; then
      echo -e "\n\nDLLs/EXEs loaded from temp folders." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/dlllist_temp.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find hidden DLLs/EXEs (ldrmodules):
    cat $output_dir/ldrmodules/ldrmodules.txt | grep -E -i "False  False  False" | sort | uniq | grep -E -i ".dll$|.exe$" > $output_dir/tmpfolder/ldrmodule_hidden.tmp
    if [[ -s $output_dir/tmpfolder/ldrmodule_hidden.tmp ]] ; then
      echo -e "\n\nDLLs/EXEs hidden from ldrmodules." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/ldrmodules/ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/ldrmodules/ldrmodules.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/ldrmodule_hidden.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # highlight prefetch files:
    cat $output_dir/mftparser/mftparser.txt | grep \.pf$ | awk '{print $NF}' | sort | uniq > $output_dir/tmpfolder/prefetch.tmp
    if [[ -s $output_dir/tmpfolder/prefetch.tmp ]]; then
      echo -e "\n\nPrefetch artifacts." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/prefetch.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # highlight binaries loaded from TEMP folders:
    cat $output_dir/envars/envars.txt | grep -i "TEMP" > $output_dir/tmpfolder/temp_envars.tmp
    if [[ -s $output_dir/tmpfolder/temp_envars.tmp ]]; then
      echo -e "\n\nPossible binaries loaded from TEMP folders (envars)." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/envars/envars.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/envars/envars.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/temp_envars.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find interesting executables (dlllist):
    cat $output_dir/dlllist/dlllist.txt | grep "Command line" | grep -E -v -i "system32|explorer.exe|iexplore.exe" | sed -e 's/Command line : //' | sort | uniq > $output_dir/tmpfolder/execs.tmp
    if [[ -s $output_dir/tmpfolder/execs.tmp ]] ; then
      echo -e "\n\nInteresting executables (dlllist)." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/execs.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # highlight alternate data stream files:
    cat $output_dir/mftparser/mftparser.txt | grep "DATA ADS" > $output_dir/tmpfolder/ads.tmp
    if [[ -s $output_dir/tmpfolder/ads.tmp ]]; then
      echo -e "\n\nAlternate Data Stream (ADS) files." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/ads.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    ################################ MALWARE CHECKS - MISC ################################

    # find interresting entries in hosts file
    mkdir $output_dir/tmpfolder/hosts
    qaddress=$(cat $output_dir/filescan/filescan.txt | grep -i -E "etc\\\\hosts$" | tr -s ' ' | cut -d ' ' -f 1)
    if [[ ! -z "$qaddress" ]] ; then 
      vol.py --profile=$profile -f $memory_image dumpfiles -Q $qaddress -D $output_dir/tmpfolder/hosts --name &> /dev/null 
      strings $output_dir/tmpfolder/hosts/* > $output_dir/tmpfolder/hosts.tmp  &> /dev/null
    fi
    if [[ -s $output_dir/tmpfolder/hosts.tmp ]] ; then
      cat $output_dir/tmpfolder/hosts.tmp | grep -v "^#"  > $output_dir/tmpfolder/interresting-hosts.tmp
      if [[ -s $output_dir/tmpfolder/interresting-hosts.tmp ]] ; then
        echo -e "\n\nEntries in hosts files." >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
        cat $output_dir/tmpfolder/interresting-hosts.tmp >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    fi

    ################################ MALWARE CHECKS - PERSISTENCE ################################

    echo -e "Searching for persistence artifacts..."

    # highlight temp folders appearing in services:
    cat $output_dir/svcscan/svcscan.txt | grep -i -E "TMP|TEMP|AppData" > $output_dir/tmpfolder/svcscan_temp.tmp
    if [[ -s $output_dir/tmpfolder/svcscan_temp.tmp ]]; then
      echo -e "\n\nTemp folders appearing in services." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/svcscan_temp.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # dump registry keys commonly used for persistence:
    mkdir $output_dir/printkey
    plugin="printkey"
    for key in "Microsoft\Windows\CurrentVersion\RunOnce" "Microsoft\Windows\CurrentVersion\Run" "Software\Microsoft\Windows\CurrentVersion\RunOnce" "Software\Microsoft\Windows\CurrentVersion\Run" "Microsoft\Windows\CurrentVersion\RunServices" "Microsoft\Windows\CurrentVersion\RunServicesOnce" "Software\Microsoft\Windows NT\CurrentVersion\Winlogon" "Microsoft\Security Center\Svc" ; do
      vol.py --profile=$profile -f $memory_image $plugin -K $key &>> $output_dir/tmpfolder/printkey.tmp
      tr < $output_dir/tmpfolder/printkey.tmp -d '\000' > $output_dir/printkey/printkey.txt
    done

    # highlight temp folders appearing in dumped registry keys:
    cat $output_dir/printkey/printkey.txt | grep -i -E "TMP|TEMP|AppData" > $output_dir/tmpfolder/printkey_temp.tmp
    if [[ -s $output_dir/tmpfolder/printkey_temp.tmp ]]; then
      echo -e "\n\nTemp folders appearing in dumped registry keys." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/printkey_temp.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    ################################ MALWARE CHECKS - KERNEL ################################

    # find keylogger traces in messagehooks:
    cat $output_dir/messagehooks/messagehooks.txt | grep -i "KEYBOARD" > $output_dir/tmpfolder/keyboard_messagehooks.tmp
    if [[ -s $output_dir/tmpfolder/keyboard_messagehooks.tmp ]]; then
      echo -e "\n\nKeylogger traces (messagehooks)." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/messagehooks/messagehooks.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/messagehooks/messagehooks.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/keyboard_messagehooks.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find unusual timers:
    tail -n +4 $output_dir/timers/timers.txt | grep -E -v -i "ataport.SYS|ntoskrnl.exe|NETIO.SYS|storport.sys|afd.sys|cng.sys|dfsc.sys|discache.sys|HTTP.sys|luafv.sys|ndis.sys|Ntfs.sys|rdbss.sys|rdyboost.sys|spsys.sys|srvnet.sys|srv.sys|tcpip.sys|usbccgp.sys" | sort | uniq >> $output_dir/tmpfolder/timers.tmp
    if [[ -s $output_dir/tmpfolder/timers.tmp ]] ; then
      echo -e "\n\ntimers." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/timers/timers.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/timers/timers.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/timers.tmp >> $output_dir/tmpfolder/malware-checks.tmp
      if [[ $@ =~ "--add-hints" ]] ; then
        echo -e "\nHint: Malware can set kernel timers to run functions at specified intervals." >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    fi

    # find unusual gditimers:
    tail -n +4 $output_dir/gditimers/gditimers.txt | grep -E -v -i "dllhost.exe|explorer.exe|csrss.exe" | sort | uniq >> $output_dir/tmpfolder/gditimers.tmp
    if [[ -s $output_dir/tmpfolder/gditimers.tmp ]] ; then
      echo -e "\n\ngditimers." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/gditimers/gditimers.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/gditimers/gditimers.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/gditimers.tmp >> $output_dir/tmpfolder/malware-checks.tmp
      if [[ $@ =~ "--add-hints" ]] ; then
        echo -e "\nHint: Malware can set timers to run functions at specified intervals." >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    fi

    # find malicious kernel timers:
    cat $output_dir/timers/timers.txt | grep -i "UNKNOWN" > $output_dir/tmpfolder/unknown_timers.tmp
    if [[ -s $output_dir/tmpfolder/unknown_timers.tmp ]]; then
      echo -e "\n\nMalicious kernel timers." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/timers/timers.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/timers/timers.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/unknown_timers.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find malicious kernel callbacks:
    cat $output_dir/callbacks/callbacks.txt | grep -i "UNKNOWN" > $output_dir/tmpfolder/unknown_callbacks.tmp
    if [[ -s $output_dir/tmpfolder/unknown_callbacks.tmp ]]; then
      echo -e "\n\nMalicious kernel callbacks." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/callbacks/callbacks.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/callbacks/callbacks.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/unknown_callbacks.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find unknown drivermodule entries:
    cat $output_dir/drivermodule/drivermodule.txt | grep -i "UNKNOWN" > $output_dir/tmpfolder/unknown_drivermodule.tmp
    if [[ -s $output_dir/tmpfolder/unknown_drivermodule.tmp ]]; then
      echo -e "\n\nNew suspicious drivermodule entries." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/drivermodule/drivermodule.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/drivermodule/drivermodule.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/unknown_drivermodule.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find unknown driverirp entries:
    cat $output_dir/driverirp/driverirp.txt | grep -i "UNKNOWN" > $output_dir/tmpfolder/unknown_driverirp.tmp
    if [[ -s $output_dir/tmpfolder/unknown_driverirp.tmp ]]; then
      echo -e "\n\nNew suspicious driverirp entries." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/unknown_driverirp.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find hooked ssdt functions:
    cat $output_dir/ssdt/ssdt.txt | grep -i -E -v '(ntos|win32k)' | grep -i "Entry" > $output_dir/tmpfolder/hooked_ssdt.tmp
    if [[ -s $output_dir/tmpfolder/hooked_ssdt.tmp ]]; then
      echo -e "\n\nHooked ssdt functions." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/hooked_ssdt.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # find suspicious idt entries:
    cat $output_dir/idt/idt.txt | grep -i "rsrc" > $output_dir/tmpfolder/manipulated_idt.tmp
    if [[ -s $output_dir/tmpfolder/manipulated_idt.tmp ]]; then
      echo -e "\n\nSuspicious idt entries." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '2p' $output_dir/idt/idt.txt >> $output_dir/tmpfolder/malware-checks.tmp
      sed -n '3p' $output_dir/idt/idt.txt >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/manipulated_idt.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    # display orphan threads:
    tail -n +4 $output_dir/orphanthreads/orphanthreads.txt > $output_dir/tmpfolder/orphanthreads.tmp
    if [[ -s $output_dir/tmpfolder/orphanthreads.tmp ]]; then
      echo -e "\n\nOrphan threads." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/orphanthreads.tmp >> $output_dir/tmpfolder/malware-checks.tmp
    fi

    ################################ MALWARE CHECKS - STRINGS ################################

    echo -e "Hunting for badness in memory strings..."

    # dump unusual processes to disk
    tail -n +4 $output_dir/psscan/psscan.txt | grep -v -i -E $usual_processes | tr -s ' ' | cut -d ' ' -f 1 > $output_dir/tmpfolder/offsets_to_dmp.tmp
    mkdir $output_dir/procdump
    while read offset ; do
      vol.py --profile=$profile -f $memory_image -o $offset procdump -D $output_dir/procdump &> /dev/null &
    done < $output_dir/tmpfolder/offsets_to_dmp.tmp
    wait

    # run volatility strings plugin against [some] processes
    mkdir $output_dir/strings
    strings -a -td $output_dir/malfind/dump-dir/* > $output_dir/tmpfolder/process-strings.tmp 2> /dev/null
    strings -a -td $output_dir/procdump/* >> $output_dir/tmpfolder/process-strings.tmp 2> /dev/null
    vol.py --profile=$profile -f $memory_image strings -S --string-file=$output_dir/tmpfolder/process-strings.tmp &> $output_dir/strings/process-strings-vol.txt

    # finding ips/domains/emails in strings:
    cat $output_dir/strings/process-strings-vol.txt | grep -E '\b(https?|ftp|file)://[-A-Za-z0-9+&@#/%?=~_|!:,.;]*[-A-Za-z0-9+&@#/%=~_|]' | uniq >> $output_dir/tmpfolder/ip-domains.tmp
    cat $output_dir/strings/process-strings-vol.txt | grep -E "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | uniq >> $output_dir/tmpfolder/ip-domains.tmp
    cat $output_dir/strings/process-strings-vol.txt | grep -E "\b[a-zA-Z0-9.-]+@[a-zA-Z0-9.-]+\.[a-zA-Z0-9.-]+\b" | uniq >> $output_dir/tmpfolder/ip-domains.tmp
    if [[ -s $output_dir/tmpfolder/ip-domains.tmp ]] ; then
      echo -e "\n\nIPs, domains and email addresses found in memory strings." >> $output_dir/tmpfolder/malware-checks.tmp
      echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
      cat $output_dir/tmpfolder/ip-domains.tmp | sort | uniq >> $output_dir/tmpfolder/malware-checks.tmp
    fi
    
    # finding other suspicious strings:
    for pattern in Web Antivirus Virtualisation Sandbox Sysinternals Shell Keylogger Filepath Password Powershell Infogathering Executable Banking Encryption Socialsites Other ; do
      if [[ $pattern == "Web" ]] ; then regex_str=$web_regex_str ; fi
      if [[ $pattern == "Antivirus" ]] ; then regex_str=$antivirus_regex_str ; fi
      if [[ $pattern == "Virtualisation" ]] ; then regex_str=$virtualisation_regex_str ; fi
      if [[ $pattern == "Sandbox" ]] ; then regex_str=$sandbox_regex_str ; fi
      if [[ $pattern == "Sysinternals" ]] ; then regex_str=$sysinternals_regex_str ; fi
      if [[ $pattern == "Shell" ]] ; then regex_str=$shell_regex_str ; fi
      if [[ $pattern == "Keylogger" ]] ; then regex_str=$keylogger_regex_str ; fi
      if [[ $pattern == "Filepath" ]] ; then regex_str=$filepath_regex_str ; fi
      if [[ $pattern == "Password" ]] ; then regex_str=$password_regex_str ; fi
      if [[ $pattern == "Powershell" ]] ; then regex_str=$powershell_regex_str ; fi
      if [[ $pattern == "Infogathering" ]] ; then regex_str=$infogathering_regex_str ; fi
      if [[ $pattern == "Executable" ]] ; then regex_str=$exec_regex_str ; fi
      if [[ $pattern == "Banking" ]] ; then regex_str=$banking_regex_str ; fi
      if [[ $pattern == "Encryption" ]] ; then regex_str=$crypto_regex_str ; fi
      if [[ $pattern == "Socialsites" ]] ; then regex_str=$socialsites_regex_str ; fi
      if [[ $pattern == "Other" ]] ; then regex_str=$other_regex_str ; fi

      if grep -E -i $regex_str $output_dir/strings/process-strings-vol.txt > /dev/null ; then
        echo -e "\n\n$pattern strings found in memory." >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
        grep -E -i $regex_str $output_dir/strings/process-strings-vol.txt | sort | uniq >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    done

    ################################ MALWARE CHECKS - IMPORTS ################################

    # analyse import tables in some processes:
    plugin=impscan
    cat $output_dir/malfind/malfind.txt | grep "Address:" | cut -d ' ' -f 4 | sort | uniq > $output_dir/tmpfolder/procids.tmp
    tail -n +4 $output_dir/psscan/psscan.txt | grep -v -E -i $usual_processes | tr -s ' ' | cut -d " " -f 3 | sort | uniq >> $output_dir/tmpfolder/procids.tmp
    cat $output_dir/tmpfolder/procids.tmp | sort | uniq > $output_dir/tmpfolder/pids.tmp

    while read pid; do
      vol.py --profile=$profile -f $memory_image $plugin -p $pid &> $output_dir/tmpfolder/$pid-imports.tmp
      process=`tail -n +4 $output_dir/psscan/psscan.txt | tr -s ' ' | cut -d ' ' -f 1-3 | grep -i " "$pid | cut -d ' ' -f 2 | sort | uniq`
      # searching for anti debug import functions
      cat $output_dir/tmpfolder/$pid-imports.tmp | grep -i -E $anti_debug_imports > $output_dir/tmpfolder/$pid-imports-susp.tmp
      # search for password extraction import functions 
      cat $output_dir/tmpfolder/$pid-imports.tmp | grep -i -E $password_extract_imports >> $output_dir/tmpfolder/$pid-imports-susp.tmp
      # searching for web request import functions
      cat $output_dir/tmpfolder/$pid-imports.tmp | grep -i -E $web_imports >> $output_dir/tmpfolder/$pid-imports-susp.tmp
      # searching for service import functions
      cat $output_dir/tmpfolder/$pid-imports.tmp | grep -i -E $service_imports >> $output_dir/tmpfolder/$pid-imports-susp.tmp
      # searching for process injection import functions
      cat $output_dir/tmpfolder/$pid-imports.tmp | grep -i -E $process_injection_imports >> $output_dir/tmpfolder/$pid-imports-susp.tmp
      # searching for uac bypass import functions
      cat $output_dir/tmpfolder/$pid-imports.tmp | grep -i -E $uac_bypass_imports >> $output_dir/tmpfolder/$pid-imports-susp.tmp
      # searching for misc import functions
      cat $output_dir/tmpfolder/$pid-imports.tmp | grep -i -E $misc_imports >> $output_dir/tmpfolder/$pid-imports-susp.tmp
      if [[ -s $output_dir/tmpfolder/$pid-imports-susp.tmp ]] ; then
        echo -e "\n\nSuspicious imports in process $process." >> $output_dir/tmpfolder/malware-checks.tmp
        echo -e "===========================================================================\n" >> $output_dir/tmpfolder/malware-checks.tmp
        sed -n '2p' $output_dir/tmpfolder/$pid-imports.tmp >> $output_dir/tmpfolder/malware-checks.tmp
        sed -n '3p' $output_dir/tmpfolder/$pid-imports.tmp >> $output_dir/tmpfolder/malware-checks.tmp
        cat $output_dir/tmpfolder/$pid-imports-susp.tmp >> $output_dir/tmpfolder/malware-checks.tmp
      fi
    done < $output_dir/tmpfolder/pids.tmp

  fi

  ################################ REPORT CREATION ################################
  if [[ $@ =~ "--no-report" ]] ; then
    endtime=$(date +%s)
    echo -e "\nAll done in $(($endtime - $starttime)) seconds."
    rm -r $output_dir/tmpfolder &> /dev/null
    notify-send "VolDiff execution completed."
    exit
  fi

  echo -e "Creating a report..."
  report=VolDiff-report.txt
  touch $output_dir/$report
  echo -e " _    __      ______  _ ________" >> $output_dir/$report
  echo -e "| |  / /___  / / __ \(_) __/ __/" >> $output_dir/$report
  echo -e "| | / / __ \/ / / / / / /_/ /_  " >> $output_dir/$report
  echo -e "| |/ / /_/ / / /_/ / / __/ __/  " >> $output_dir/$report
  echo -e "|___/\____/_/_____/_/_/ /_/     " >> $output_dir/$report
  echo -e "\nVolatility analysis report generated by VolDiff v$version." >> $output_dir/$report 
  echo -e "Download the latest VolDiff version from https://github.com/aim4r/VolDiff/.\n" >> $output_dir/$report
  echo -e "Memory image: $memory_image" >> $output_dir/$report
  echo -e "Profile: $profile" >> $output_dir/$report 
  touch $output_dir/tmpfolder/no_new_entries.tmp

  for plugin in "${plugins_to_report_standalone[@]}" ; do
    tail -n +2 $output_dir/$plugin/$plugin.txt > $output_dir/tmpfolder/output_test.tmp
    if [[ -s $output_dir/tmpfolder/output_test.tmp ]] ; then
      echo -e "\n\n$plugin output." >> $output_dir/$report
      echo -e "===========================================================================\n" >> $output_dir/$report
      tail -n +2 $output_dir/$plugin/$plugin.txt >> $output_dir/$report
      # adding hints to help in further analysis:
      if [[ $@ =~ "--add-hints" ]] ; then
        if [[ $plugin = "malfind" ]] ; then
          echo -e "\nHint: Suspicious malfind processes were dumped to disk, and can be reversed as normal or uploaded to VirusTotal." >> $output_dir/$report
        fi
        if [[ $plugin = "psscan" ]] ; then
          echo -e "\nHint: Use procexedump to dump suspcious processes from memory to disk." >> $output_dir/$report
        fi
        if [[ $plugin = "netscan" ]] ; then
          echo -e "\nHint: Translate suspicious IPs to domains using Google/VirusTotal, and search for the associated domains in memory strings." >> $output_dir/$report
        fi
        if [[ $plugin = "iehistory" ]] ; then
          echo -e "\nHint: iehistory can reveal history details of malware that uses the WinINet API." >> $output_dir/$report
        fi
      fi
    else
      echo -e "$plugin" >> $output_dir/tmpfolder/no_new_entries.tmp 
    fi
  done

  # display list of plugins with no notable changes:
  if [[ -s $output_dir/tmpfolder/no_new_entries.tmp ]]; then
    echo -e "\n\nNo output to highlight for the following plugins." >> $output_dir/$report
    echo -e "===========================================================================\n" >> $output_dir/$report
    cat $output_dir/tmpfolder/no_new_entries.tmp >> $output_dir/$report
  fi

  # display list of plugins hidden from report:
  echo -e "\n\nPlugins that were executed but are not included in the report." >> $output_dir/$report
  echo -e "===========================================================================\n" >> $output_dir/$report
  echo -e "handles\ngetsids\npslist\ndlllist\nfilescan\nshimcache\nsvcscan\nshelbags\nsessions\nmessagehooks\neventhooks\nenvars\nmutantscan\natoms\natomscan\ndrivermodule\ndriverscan\ndevicetree\nmodules\nmodscan\nunloadedmodules\ncallbacks\nldrmodules\nprivs\norphanthreads\nidt\ngdt\ndriverirp\ndeskscan\ntimers\ngditimers\nssdt" >> $output_dir/$report

  # add identified process anomalies to the report:
  if [[ $@ =~ "--malware-checks" ]] ; then
    if [[ -s $output_dir/tmpfolder/malware-checks.tmp ]]; then
      echo -e "" >> $output_dir/$report
      echo "   _               _           _         __                 _ _       " >> $output_dir/$report
      echo "  /_\  _ __   __ _| |_   _ ___(_)___    /__\ ___  ___ _   _| | |_ ___ " >> $output_dir/$report
      echo -E " //_\\\\| '_ \\ / _\` | | | | / __| / __|  / \\/// _ \\/ __| | | | | __/ __|" >> $output_dir/$report
      echo -E "/  _  \\ | | | (_| | | |_| \\__ \\ \\__ \\ / _  \\  __/\\__ \\ |_| | | |_\\__ \\" >> $output_dir/$report
      echo "\_/ \_/_| |_|\__,_|_|\__, |___/_|___/ \/ \_/\___||___/\__,_|_|\__|___/" >> $output_dir/$report
      echo "                     |___/                                            " >> $output_dir/$report
      cat $output_dir/tmpfolder/malware-checks.tmp >> $output_dir/$report
    fi
  fi

  echo -e "\n\nEnd of report." >> $output_dir/$report
  rm -r $output_dir/tmpfolder &> /dev/null
  endtime=$(date +%s)
   echo -e "\nAll done in $(($endtime - $starttime)) seconds, report saved to $output_dir/$report."
  notify-send "VolDiff execution completed."

fi
