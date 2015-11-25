import paramiko
import logging
import re
import socket

class customSSH:
    def __init__( self, host, port, user, passwd, target ):
        self.prompts = {
            "cisco":    ("#"),
            "huawei":   (">","]", "[Y/N]:"),
            "sso":      ("Type to search or select one:")
        }
        self.regexes = {
            "cisco":re.compile(r'.*(nw_.*#)'),
            "huawei":re.compile(r'.*(<nw_.*>)')
        }
        self.vendorName = ""
        self.hostname = ""
        self.initialCommands = {
            "cisco":  [ "terminal length 0" ],
            "huawei": [ "system-view", "screen-width 512", "Y", "quit", "screen-length 0 temporary" ]
        }



        if target is not None:
            verboseMessage = "SSO Server ("+host+":"+str(port)+")"
        else:
            verboseMessage = host+":"+str(port)

        try:
            self.sshObj = paramiko.SSHClient()
            self.sshObj.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            logging.info("Connecting to "+verboseMessage)
            self.sshObj.connect(
                host,
                port=port,
                username=user,
                password=passwd,
                timeout=10,
                compress=True,
                allow_agent=False,
                look_for_keys=False)

            logging.info("Connected to "+verboseMessage)
            try:
                self.chanObj = self.sshObj.invoke_shell( width=255 )
                self.chanObj.settimeout(10)
            except:
                raise ValueError("Unable to invoke shell on SSO")

            if target > 0:
                logging.info("Connecting to "+target+" via SSO Server")
                self.chanObj.send(target+"\r")
                buff = ''
                currPrompt = self.prompts["cisco"]
                while len([name for name in self.prompts if buff.endswith(self.prompts[name])]) < 1: #buff.endswith(tuple(self.prompts)):
                    resp = self.chanObj.recv(1024)
                    buff += resp
                    logging.debug("["+target+"] BUFF> "+resp)
                    for regexName, regexValue in self.regexes.iteritems():
                        logging.debug("["+target+"] VENDOR> Trying "+regexName)
                        match = regexValue.search(resp)
                        if (match is not None):
                            logging.info("["+target+"] > Identified target vendor as "+regexName)
                            currPrompt = self.prompts[regexName]
                            self.vendorName = regexName
                            self.hostname = str(match.group(0))
                            break

                    if len(self.vendorName):
                        break

            # Run initial commands
            logging.info("["+target+"] > Running Initial Commands")
            for initCmd in self.initialCommands[self.vendorName]:
                logging.debug("["+target+"] > Invoking fetchData("+initCmd+")")
                self.fetchData ( initCmd )
            logging.info("["+target+"] > All initial commands ran.")

        except paramiko.ssh_exception.AuthenticationException:
            raise ValueError("Authentication failure on SSO Server!")
        except socket.timeout:
            raise ValueError("Timed out on "+host+" / "+target+" !!")

    def fetchData( self, cmd, regex = None ):
        logging.info("["+self.hostname+"] # "+str(cmd)+" with "+str(self.prompts[self.vendorName]))
        self.chanObj.send(''+str(cmd)+'\r')
        buff = ''

        found = False
        while found is False:
             resp = self.chanObj.recv(10240)
             buff += resp
             logging.debug("["+self.hostname+"] BUFF> "+resp)
             found = buff.endswith(self.prompts[self.vendorName])
        logging.debug("["+self.hostname+"] < Received "+str(len(buff))+' bytes')

        if ( regex is not None ):
            logging.debug("["+self.hostname+"] ?  Searching for "+regex+" in the buffer")
            searchFor = re.compile(r''+regex)
            match = searchFor.search(buff)
            if (match is not None):
                logging.debug("["+self.hostname+"] ?= Found "+str(len(match.groups()))+" matches")
                logging.debug("["+self.hostname+"] Matches : "+str(match.groups()))
                return match.groups()
            else:
                logging.debug("["+self.hostname+"] ?! Could not match anything")
                raise ValueError("Can not match given regex in the data")
        else:
            return str(buff)

    def disconnect (self):
        self.sshObj.close()
        logging.info("["+self.hostname+"] < Disconnected")
