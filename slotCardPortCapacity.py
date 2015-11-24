# -*- coding: utf8 -*-
from customNetworkLibs import physicalDiscovery
import logging
import multiprocessing
import os
import argparse
import sys

sys.stdout.flush()

__progName__ = "slotCordPortCapacity"
__author__ = "Emre Erkunt"
__copyright__ = "Copyright 2015, Emre Erkunt"
__credits__ = []
__license__ = "GPL"
__version__ = "0.1.1 Beta"
__maintainer__ = "Emre Erkunt"
__email__ = "emre.erkunt at gmail.com"
__status__ = "Development"

# Defaults
defOutputFile = "output.csv"
defDelimeter = ","

# Argument Handling
class argHandling(object):
    pass

args = argHandling();
parser = argparse.ArgumentParser(prog=__progName__, description="This scripts reads a list of IPs and fetches physical inventory data via Single Sign On Server")
parser.add_argument("--version", action="version", version='%(prog)s '+__version__, help="Show version")
parser.add_argument("--output", "-o", dest='outputFile', metavar='FILENAME', type=argparse.FileType('w'), default=defOutputFile, help="Filtered results will be written on this output in CSV format.")
parser.add_argument("--input", "-i", dest="inputFile", required=True, metavar="FILENAME", type=file, default=False, help="Input file that will be parsed ( must be a list of NEs IP or hostname )")
parser.add_argument("--delimeter", "-d", dest='delimeter', metavar='DELIMETER', nargs='?', default=defDelimeter, help="Use given delimeter in CSV format. Default is \""+defDelimeter+"\"")
parser.parse_args(namespace=args)

# You need to declare logging otherwise it won't work :)
logging.basicConfig(filename='app.log', filemode='a', level=logging.INFO, format='%(asctime)s [%(name)s] %(levelname)s: %(message)s')

if os.access(args.inputFile.name, os.R_OK) is False:
	print "Can not read "+args.inputFile.name
	exit(-1)

if os.access(args.outputFile.name, os.W_OK) is False:
	print "Can not write into "+args.outputFile.name
	exit(-1)

targets = args.inputFile.readlines()

print __progName__,"v"+__version__
print str(len(targets))+" targes acquired."
maxThreads = 5
logging.debug("Max threads set to "+str(maxThreads))
if ( len(targets) < maxThreads ):
	maxThreads = len(targets)
	logging.debug("Max threads changed to "+str(maxThreads))

print "Running with "+str(maxThreads)+" threads."
logging.info("Multi-threading initiated with "+str(maxThreads)+" threads.")

global fd
global delimeter
delimeter = ","
headerTxt = [ "\"CI Name\"", "\"IP Address\"", "\"Slot\"", "\"Card\"", "\"Port\"", "\"SFP Type\"", "\"SFP Vendor\"", "\"Bandwidth\"", "\"State\"", "\"Description\"" ]
delim = delimeter+" "
headerRow = delim.join(headerTxt)+"\n"
args.outputFile.write(headerRow)
resultArray = dict()

print "Discovery started."
threads = multiprocessing.Pool(maxThreads)
resultArray = threads.map( physicalDiscovery.discover, targets )

''' Dump inventory data into the CSV file '''
print "Discovery finished."
print "Writing to "+args.outputFile.name
for target in resultArray:
	print "--> "+str(target[0])
	for card in target[2]:
		for slot in target[2][card]:
			for port in target[2][card][slot]:
				card = str(card)
				slot = str(slot)
				port = str(port)

				output  = "\""+str(target[1])+"\""+delim
				output += "\""+str(target[0])+"\""+delim
				output += "\""+str(slot)+"\""+delim+"\""+str(card)+"\""+delim+"\""+str(port)+"'"+delim
				if 'SFPType' in target[2][str(slot)][str(card)][str(port)]:
					output += "\""+str(target[2][slot][card][port]['SFPType'])+"'"+delim
					output += "\""+str(target[2][slot][card][port]['SFPRange'])+"'"+delim
				else:
					output += "\"\""+delim+"\"\""+delim
				output += "\""+str(target[2][slot][card][port]['status'])+"\""+delim
				output += "\""+str(target[2][slot][card][port]['description'])+"\"\n"
				args.outputFile.write(output)

logging.info("All finished.")
print "\nAll finished.\n"
