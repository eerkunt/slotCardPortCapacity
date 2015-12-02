import customSsh
import logging
import re
import __builtin__
import multiprocessing

ssoServer = __builtin__.ssoServer
sshCredentials = __builtin__.sshCredentials

STDOUT = ""


def add2Layout(ports, slot, card, port, key, value):
    slot = str(slot)
    card = str(card)
    port = str(port)
    key = str(key)
    value = str(value)

    logging.debug(
        "-> Adding New value to Port " + slot + "/" + card + "/" + port + " as " + key + ":" + value + " into " + str(
            type(ports)))

    if (slot not in ports):
        ports[slot] = dict()
        logging.debug("-> Created structure Layer 1")
    if (card not in ports[slot]):
        ports[slot][card] = dict()
        logging.debug("-> Created structure Layer 2")
    if (port not in ports[slot][card]):
        ports[slot][card][port] = dict()
        logging.debug("-> Created structure Layer 3")

    ports[slot][card][port][key] = value
    return


def discover(hostname):
    hostname = hostname.strip()
    commandSet = {
        "cisco":
            [
                'sh ver | i uptime',
                'sh int des',
                'sh int des',
                'show controllers _INTERFACE_ phy'
            ],
        "huawei":
            [
                'disp cur | i sysname',
                'dis int b',
                'dis int des',
                'disp int _INTERFACE_'
            ]
    }

    regexSet = {
        "cisco":
            [
                '(.*) uptime is .*',
                ['(Gi\d*\/(\d*)\/(\d*)\/(\d*))\s+', '(Te\d*\/(\d*)\/(\d*)\/(\d*))\s+'],
                '_INTERFACE_\s*([updown\-ami]+)\s*[updown\-ami]+\s*(.*)',
                ['\s*Xcvr Code: (.*)', '\s*Vendor Name: (.*)'],
            ],
        "huawei":
            [
                'sysname (.*)',
                ['(GigabitEthernet(\d*)\/(\d*)\/(\d*))\s+', '(GigabitEthernet(\d*)\/(\d*)\/(\d*))\(10G\)\s+'],
                'GE_SLOT_\/_CARD_\/_PORT_\s*([\*updown]+)\s*[\*updown]+\s*(.*)',
                ['\s*WaveLength: \d*nm, Transmission Distance: (.*)', '\s*The Vendor Name is (.*)']
            ]
    }
    STDOUT = hostname + "> "
    try:
        target = customSsh.customSSH(ssoServer, sshCredentials["port"], sshCredentials["username"],
                                     sshCredentials["password"], hostname)
    except ValueError as err:
        print "ERROR: " + err.args[0]
        exit(0)
    STDOUT += "[" + target.hostname + "] [" + target.vendorName + "] "

    ciName = target.fetchData(commandSet[target.vendorName][0], regexSet[target.vendorName][0])
    STDOUT += "(" + str(ciName[0]).strip() + ") "

    inventory = dict()
    gigPorts = 0
    tenGigPorts = 0

    response = target.fetchData(commandSet[target.vendorName][1]).splitlines()

    # This will be used for skipping any ports defined in ignoreList array
    ignoreList = ["GigabitEthernet0/0/0"]

    for line in response:
        GiEthRegex = re.compile(r'' + str(regexSet[target.vendorName][1][0]))
        TenEthRegex = re.compile(r'' + str(regexSet[target.vendorName][1][1]))
        match = GiEthRegex.search(line)

        # GigabitEthernet Ports
        if (match is not None):
            matches = list()
            for i in range(len(match.groups()) + 1):
                matches.append(match.group(i).strip())
            logging.debug("[" + target.hostname + "] Matches : " + str(matches))
            logging.debug(
                "[" + target.hostname + "] Found a gigabit port ! ( " + match.group(0).strip() + " ) Curr:" + str(
                    gigPorts))
            if (matches[1] not in ignoreList):
                add2Layout( ports=inventory,
                            slot=matches[2],
                            card=matches[3],
                            port=matches[4],
                            key="name",
                            value=matches[1] )
                add2Layout( ports=inventory,
                            slot=matches[2],
                            card=matches[3],
                            port=matches[4],
                            key="bandwidth",
                            value=1 )
                gigPorts += 1
            else:
                logging.debug( "[" +target. hostname + "] Skipping " +matches[1 ] +" as it is in ignored list.")
        else:
            # Ten Gigabit Ethernet Ports
            match = TenEthRegex.search(line)
            if ( match is not None ):
                matches = list()
                for i in range(len(match.groups() ) +1):
                    matches.append( match.group(i).strip() )
                logging.debug( "[" +target. hostname + "] Matches : " +str(matches))
                logging.debug \
                    ( "[" +target. hostname + "] Found a ten gigabit port ! ( " +match.group(0 ) + " ) Curr:" +str
                        (tenGigPorts))
                if ( matches[1] not in ignoreList ):
                    add2Layout( 	ports=inventory,
                                    slot=matches[2],
                                    card=matches[3],
                                    port=matches[4],
                                    key="name",
                                    value=matches[1] )
                    add2Layout( 	ports=inventory,
                                    slot=matches[2],
                                    card=matches[3],
                                    port=matches[4],
                                    key="bandwidth",
                                    value=10 )
                    tenGigPorts += 1
                else:
                    logging.debug( "[" +target. hostname + "] Skipping " +matches[1 ] +" as it is in ignored list.")

    logging.info( "[" +target. hostname + "] Found " +str(gigPorts ) + "x1G + " +str(tenGigPorts ) +"x10G ports")
    # print json.dumps(ports,sort_keys=True, indent=4)
    STDOUT += "["+ str(gigPorts) + "x1G + " + str(tenGigPorts) + "x10G]"

    ''' This command is for fetching descriptions. This should not be executed per port, just run for once and parse the output '''
    responseToBeParsed = target.fetchData(commandSet[target.vendorName][2])

    for slot in inventory:
        # print "Slot: "+slot
        for card in inventory[slot]:
            # print "Card: "+card
            for port in inventory[slot][card]:

                ''' We parse related description and port status on this section. '''
                regexElement = regexSet[target.vendorName][2]
                regexElement = regexElement.replace("_INTERFACE_",
                                                    inventory[slot][card][port]["name"].replace("/", "\\/"))
                regexElement = regexElement.replace("_SLOT_", slot)
                regexElement = regexElement.replace("_CARD_", card)
                regexElement = regexElement.replace("_PORT_", port)
                descrRegex = re.compile(r'' + regexElement)
                logging.debug(
                    "[" + target.hostname + "] Compiled description and status regexes. (" + regexElement + ")")
                for line in responseToBeParsed.split("\n"):
                    match = descrRegex.search(line)
                    if (match is not None):
                        logging.debug("Found a description " + str(match.groups()))
                        inventory[slot][card][port]["status"] = match.group(1).strip()
                        inventory[slot][card][port]["description"] = match.group(2).strip()
                        break

                ''' Since we have multiple elements in regexSet[vendor][3]
                we need to change every one of them. This section contains SFP related parsing '''
                sfpRegex = list()
                for regexElement in regexSet[target.vendorName][3]:
                    sfpRegex.append(re.compile(r'' + regexElement))
                    logging.debug("[" + target.hostname + "] Compiled a SFP Regex. (" + regexElement + ")")

                ''' This command is for fetching SFP Related data. '''
                command = commandSet[target.vendorName][3]
                command = command.replace("_INTERFACE_", inventory[slot][card][port]["name"])
                responseToBeParsedSFP = target.fetchData(command)
                for line in responseToBeParsedSFP.split("\n"):
                    match = sfpRegex[0].search(line)
                    if (match is not None):
                        logging.debug("Found a SFP Type " + str(match.groups()))
                        inventory[slot][card][port]["SFPType"] = match.group(1).strip()

                    match = sfpRegex[1].search(line)
                    if (match is not None):
                        logging.debug("Found a SFP Range data " + str(match.groups()))
                        inventory[slot][card][port]["SFPRange"] = match.group(1).strip()

    # print STDOUT
    return [hostname.strip(), ciName[0].strip(), inventory]

# target.disconnect()
