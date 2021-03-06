# -*- coding: utf8 -*-
import logging
from progressbar import *
import threading
import os
import argparse
import sys
import __builtin__
import getpass

### slotCardPortCapacity Script for discovering physical data from network via SSH ( with or w/out a Proxy Server ) ###
# todo Beautify with terminal colors who is already supported with Win32 Terminal, OSX and Linux.
# todo show some swirling or any progress from other threads while in discovery if possible.
# todo keyboard interrupts

sys.stdout.flush()

__progName__ = "slotCardPortCapacity"
__author__ = "Emre Erkunt"
__copyright__ = "Copyright 2015, Emre Erkunt"
__credits__ = []
__license__ = "GPL"
__version__ = "0.1.8"
__maintainer__ = "Emre Erkunt"
__email__ = "emre.erkunt at gmail.com"
__status__ = "Development"

# Defaults
defOutputFile = "output.csv"
defDelimeter = ";"
defSsoIP = "10.35.175.1"
defPort = 2222
defThreads = 5
maxThreads = 20

# Argument Handling
class argHandling(object):
    pass

args = argHandling()
parser = argparse.ArgumentParser(prog=__progName__,
                                 description="This scripts reads a list of IPs and fetches physical inventory data via Single Sign On Server")
parser.add_argument("--username", "-u", dest='sshUser', metavar='USERNAME', nargs='?', required=True,
                    help="Username that is required to connect SSO or NE")
parser.add_argument("--password", "-p", dest='sshPass', metavar='PASSWORD', nargs='?',
                    help="Password that is required to connect SSO or NE")
parser.add_argument("--port", "-P", dest='sshPort', metavar='PORT', nargs='?', default=defPort,
                    help="TCP Port that will be used for SSH. Default : " + str(defPort) + " (via SSO)")
parser.add_argument("--sso", "-s", dest="ssoIP", metavar="SSOIP", nargs='?', default=defSsoIP,
                    help="SSO Server IP. Default: " + defSsoIP)
parser.add_argument("--version", action="version", version='%(prog)s ' + __version__, help="Show version")
parser.add_argument("--output", "-o", dest='outputFile', metavar='FILENAME', type=argparse.FileType('w'),
                    default=defOutputFile, help="Filtered results will be written on this output in CSV format.")
parser.add_argument("--input", "-i", dest="inputFile", required=True, metavar="FILENAME", type=file, default=False,
                    help="Input file that will be parsed ( must be a list of NEs IP or hostname )")
parser.add_argument("--delimeter", "-d", dest='delimeter', metavar='DELIMETER', nargs='?', default=defDelimeter,
                    help="Use given delimeter in CSV format. Default is \"" + defDelimeter + "\"")
parser.add_argument("--threads", "-t", dest='threads', metavar='THREADS', nargs='?', default=defThreads,
                    help="Thread count. Default is \"" + str(defThreads) + "\"")
parser.parse_args(namespace=args)

# You need to declare logging otherwise it won't work :)
logging.basicConfig(filename='app.log', filemode='a', level=logging.INFO,
                    format='%(asctime)s [%(name)s] %(levelname)s (%(threadName)-10s): %(message)s')

if os.access(args.inputFile.name, os.R_OK) is False:
    print "Can not read " + args.inputFile.name
    exit(-1)

if os.access(args.outputFile.name, os.W_OK) is False:
    print "Can not write into " + args.outputFile.name
    exit(-1)

if args.sshPass is None:
    args.sshPass = getpass.getpass("Password: ")

targets = args.inputFile.readlines()

print __progName__, "v" + __version__
print str(len(targets)) + " targets acquired."

args.threads = int(args.threads)

logging.debug("Thread count given in argument is " + str(args.threads)+". Maximum threads limit set to " + str(maxThreads))
if args.threads > maxThreads:
    args.threads = maxThreads
    logging.debug("Given thread count argument is bigger than "+str(maxThreads)+". Reducing it to "+str(args.threads)+".")

logging.debug("Thread count set to " + str(args.threads))
if (len(targets) < args.threads):
    args.threads = len(targets)
    logging.debug("Max threads changed to " + str(args.threads))

print "Running with " + str(args.threads) + " threads."
logging.info("Multi-threading initiated with " + str(args.threads) + " threads.")

delimeter = args.delimeter
headerTxt = ["\"CI Name\"", "\"IP Address\"", "\"Slot\"", "\"Card Type\"", "\"Control Card Type\"", "\"Card\"", "\"Port\"", "\"SFP Type\"", "\"SFP Vendor\"",
             "\"Bandwidth\"", "\"State\"", "\"Description\""]
delim = delimeter + " "
headerRow = delim.join(headerTxt) + "\n"
args.outputFile.write(headerRow)
resultArray = list()

__builtin__.ssoServer = args.ssoIP
__builtin__.sshCredentials = {
    "username": args.sshUser,
    "password": args.sshPass,
    "port": defPort
}


from customNetworkLibs import physicalDiscovery
class ActivePool(object):
    def __init__(self):
        super(ActivePool, self).__init__()
        self.active = []
        self.targetsDown = 0
        self.lock = threading.Lock()

    def createThread(self, name):
        with self.lock:
            self.active.append(name)
            # print "Thread #"+str(len(self.active))+" initialized!"
            pbar.update(self.targetsDown)

    def killThread(self, name):
        global targets

        with self.lock:
            self.active.remove(name)
            # print "Thread #"+str(len(self.active))+" completed it's job."
            self.targetsDown += 1
            # print str(self.targetsDown)+" targets down in total!"
            widgets = ['Gathering Data : ', Percentage(),' ',Bar(marker="#"),' Please wait..']
            pbar.update(self.targetsDown)


def worker(s, pool, target, events):
    global resultArray

    if events.is_set():
        # print 'Waiting to join the pool'
        with s:
            name = threading.currentThread().getName()
            pool.createThread(name)
            try:
                resultArray.append(physicalDiscovery.discover( target ))
            except KeyboardInterrupt:
                print "Quitting"

            pool.killThread(name)

pool = ActivePool()
events = threading.Event()
events.set()
s = threading.Semaphore( args.threads )
widgets = ['Gathering Data : ', Percentage(),' ',Bar(marker="#"),' [Processing '+str(len(targets)-pool.targetsDown)+' NEs]']
print "Discovery Started. Wait for a bit for progress..\n"
pbar = ProgressBar(widgets=widgets, maxval=len(targets)).start()
for target in targets:
    t = threading.Thread(target=worker, name=str(target.strip()), args=(s, pool, target.strip(), events ))
    t.start()

try:
    t.join(1)
    time.sleep(1)
except (KeyboardInterrupt, SystemExit):
    print "Finishing.."
    events.clear()
    sys.exit(0)

if events.is_set():
    while threading.activeCount()>1:
        for thread in threading.enumerate():
            try:
                thread.join(1)
            except (KeyboardInterrupt, SystemExit):
                events.clear()
                print "Finishing.."
            except:
                pass
''' Multithreading finishes here '''

''' Dump inventory data into the CSV file '''
print "\n\nDiscovery finished."
# print resultArray

print "Writing data collected from "+str(len(resultArray))+" NEs into "+ args.outputFile.name
for target in resultArray:
    sys.stdout.write("--> " + str(target[0])+" ("+target[1]+") [")
    for slot in target[2]:
        for card in target[2][slot]["cards"]:
            sys.stdout.write(".")
            for port in target[2][slot]["cards"][card]:
                card = str(card)
                slot = str(slot)
                port = str(port)

                output = [target[1], target[0], slot]
                slotElements = ["Card", "ControlCard"]
                for element in slotElements:
                    if element in target[2][slot]:
                        output.append(target[2][slot][element])
                    else:
                        output.append("")

                output.append(card)
                output.append(port)

                portElements = ["SFPType", "SFPRange", "bandwidth", "status", "description"]
                for element in portElements:
                    if element in target[2][slot]['cards'][card][port]:
                        output.append(target[2][slot]['cards'][card][port][element])
                    else:
                        output.append("")

                args.outputFile.write(delim.join(output)+"\n")
    sys.stdout.write("]\n")
logging.info("All finished.")
print "\nAll finished.\n"
