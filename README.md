# slotCardPortCapacity
Multi-threaded Slot/Card/Port Discovery Script

This script is used for **Physical Discovery** on **Slot**, **Card** and **Port** level for specialized *Cisco* and *Huawei* Network Equipments.

# Requirements
## Running Packaged .exe File
You don't need to install anything to run [slotCardPortCapacity.exe](https://github.com/eerkunt/slotCardPortCapacity/blob/sol/dist/slotCardPortCapacity.exe?raw=true) in your Windows environment.

## Running Python Script
The requirements are listed as below to run [slotCardPortCapacity.py](https://github.com/eerkunt/slotCardPortCapacity/blob/sol/slotCardPortCapacity.py) :

1. threading enabled in Python ( most installations are already have this )
  
   To be sure that threading is enabled in your installation :
   
   ```
   ~# python -c "import threading"
   ```
2. ProgressBar

   ```
   pip install progressbar
   ```
3. Paramiko 
   
   ```
   pip install paramiko
   ```
# Usage

```
usage: slotCardPortCapacity [-h] --username [USERNAME] --password [PASSWORD]
                            [--port [PORT]] [--sso [SSOIP]] [--version]
                            [--output FILENAME] --input FILENAME
                            [--delimeter [DELIMETER]] [--threads [THREADS]]

This scripts reads a list of IPs and fetches physical inventory data via
Single Sign On Server

optional arguments:
  -h, --help            show this help message and exit
  --username [USERNAME], -u [USERNAME]
                        Username that is required to connect SSO or NE
  --password [PASSWORD], -p [PASSWORD]
                        Password that is required to connect SSO or NE
  --port [PORT], -P [PORT]
                        TCP Port that will be used for SSH. Default : 2222
                        (via SSO)
  --sso [SSOIP], -s [SSOIP]
                        SSO Server IP. Default: 10.35.175.1
  --version             Show version
  --output FILENAME, -o FILENAME
                        Filtered results will be written on this output in CSV
                        format.
  --input FILENAME, -i FILENAME
                        Input file that will be parsed ( must be a list of NEs
                        IP or hostname )
  --delimeter [DELIMETER], -d [DELIMETER]
                        Use given delimeter in CSV format. Default is ";"
  --threads [THREADS], -t [THREADS]
                        Thread count. Default is "5"
```

`-u/--username`, `-p/--password` and `-i/--input` parameters are mandatory. Others are optional. 

Script has been limited to maximum 20 threads to avoid resource hogging. If you think this is not sufficient for you, you can always change Default settings configured in the script itself ;

```python
# Defaults
defOutputFile = "output.csv"
defDelimeter = ";"
defSsoIP = "10.35.175.1"
defPort = 2222
defThreads = 5
maxThreads = 20
```
# Input File

Input fie is merely a plain text file consisting IP Addresses/Hostnames line by line. 

# Outputs

Outputs are given in CSV format. `-d/--delimeter` parameter is used for the delimeter in CSV files. Default is `;`

# License
Script is GPL v3 licensed. You can do whatever you want. It is completely free ( as also in beer ) to use, distribute, sell and change. Just follow up GPL v3 rules ;)