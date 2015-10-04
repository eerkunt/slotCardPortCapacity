#
#
# slotCardPortCapacity  -    This script finds and reports physical entities like slot, card and  
#                            port on given list of NEs. 
#
# Author            Emre Erkunt
#                   (emre.erkunt@superonline.net)
#
# History :
# -----------------------------------------------------------------------------------------------
# Version               Editor          Date            Description
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
# 0.0.1_AR              EErkunt         20141224        Initial ALPHA Release
# 0.0.1                 EErkunt         20141224        Initial Live Release
# 0.0.2                 EErkunt         20141125        Added SFP Vendor and SFP Type functions
# 0.0.3                 EErkunt         20141225        Added some outputs and swirl functionality
#                                                       Fixed some problems on CSV output
#                                                       Fixed auto-updater user/pass problem
# 0.0.4                 EErkunt         20141225        Increased max thread count from 15 to 30
# 0.0.5                 EErkunt         20141225        Again auto-updater fix :(
# 0.0.6                 EErkunt         20141226        Re-structured the whole auto-updater !!
# 0.0.7                 EErkunt         20150105        Showing 1G ports also in STDOUT
#                                                       Added an ignore list for management ports
#                                                       Fixed an SFP discovery problem
# 0.0.8                 EErkunt         20150107        Implemented RFC 1037 for stupid Huawei NEs
# 0.0.9                 EErkunt         20150108        Added unique IP input functionality
#                                                       Added subinterface discard functionality
# 0.1.0                 EErkunt         20150115        Asks for password if -p is not used
# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
#
# Needed Libraries
#
use threads;
use threads::shared;
use Getopt::Std;
use Net::Telnet qw(TELNET_IAC TELNET_SB TELOPT_NAWS TELNET_SE TELOPT_TTYPE);
use Graph::Easy;
use LWP::UserAgent;
use HTTP::Headers;
use LWP::Simple;
use Statistics::Lite qw(:all);
use Data::Dumper;
use Term::ReadPassword::Win32;

my $version     = "0.1.0";
my $arguments   = "u:p:i:o:hvt:ga:nq";
my $MAXTHREADS	= 30;
getopts( $arguments, \%opt ) or usage();
if ( $opt{q} ) {
	$opt{debug} = 1;		# Set this to 1 to enable debugging
}
$| = 1;
print "slotCardPortCapacity v".$version;
usage() if ( !$opt{u} or !$opt{p} );
usage() if (!$opt{i} or !$opt{u} or !$opt{p});
$opt{o} = "OUT_".$opt{i} unless ($opt{o});
$opt{t} = 2 unless $opt{t};
if ($opt{v}) {
	$opt{v} = 0;
} else {
	$opt{v} = 1;
}

my @targets :shared;
my @ciNames;
our @ignoreList :shared = ( 'GigabitEthernet0/0/0' ); 
unlink('upgradescpc.bat');

my $time = time();

$SIG{INT} = \&interrupt;
$SIG{TERM} = \&interrupt;

$ua = new LWP::UserAgent;
my $req = HTTP::Headers->new;

my $svnrepourl  = "http://10.34.219.5/repos/scripts/slotCardPortCapacity/"; # Do not forget the last /
my $SVNUsername = "scpe";
my $SVNPassword = "Nx91nV-1!";
my $SVNScriptName = "slotCardPortCapacity.pl";
my $SVNFinalEXEName = "scpc";

unless ($opt{n}) {
	#
	# New version checking for upgrade
	#
	$req = HTTP::Request->new( GET => $svnrepourl.$SVNScriptName );
	$req->authorization_basic( $SVNUsername, $SVNPassword );
	my $response = $ua->request($req);
	my $publicVersion;
	my $changelog = "";
	my $fetchChangelog = 0;
	my @responseLines = split(/\n/, $response->content);
	foreach $line (@responseLines) {
		if ( $line =~ /^# Needed Libraries/ ) { $fetchChangelog = 0; }
		if ( $line =~ /^my \$version     = "(.*)";/ ) {
			$publicVersion = $1;
		} elsif ( $line =~ /^# $version                 \w+\s+/g ) {
			$fetchChangelog = 1;
		} 
		if ( $fetchChangelog eq 1 ) { $changelog .= $line."\n"; }
	}
	if ( $version ne $publicVersion and length($publicVersion)) {		# SELF UPDATE INITIATION
		print "\nSelf Updating to v".$publicVersion.".";
		$req = HTTP::Request->new( GET => $svnrepourl.$SVNFinalEXEName.'.exe' );
		$req->authorization_basic( $SVNUsername, $SVNPassword );
		if($ua->request( $req, $SVNFinalEXEName.".tmp" )->is_success) {
			print "\n# DELTA CHANGELOG :\n";
			print "# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\n";
			print "# Version               Editor          Date            Description\n";
			print "# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\n";
			print $changelog;
			open(BATCH, "> upgrade".$SVNFinalEXEName.".bat");
			print BATCH "\@ECHO OFF\n";
			print BATCH "echo Upgrading started. Ignore process termination errors.\n";
			print BATCH "sleep 1\n";
			print BATCH "taskkill /F /IM ".$SVNFinalEXEName.".exe > NULL 2>&1\n";
			print BATCH "sleep 1\n";
			print BATCH "ren ".$SVNFinalEXEName.".exe ".$SVNFinalEXEName."_to_be_deleted  > NULL 2>&1\n";
			print BATCH "copy /Y ".$SVNFinalEXEName.".tmp ".$SVNFinalEXEName.".exe > NULL 2>&1\n";
			print BATCH "del ".$SVNFinalEXEName.".tmp > NULL 2>&1\n";
			print BATCH "del ".$SVNFinalEXEName."_to_be_deleted > NULL 2>&1\n";
			print BATCH "del NULL\n";
			print BATCH "echo All done. Please run the ".$SVNFinalEXEName." command once again.\n\n";
			close(BATCH);
			print "Initiating upgrade..\n";
			sleep 1;
			exec('cmd /C upgrade'.$SVNFinalEXEName.'.bat');
			exit;
		} else {
			print "Can not retrieve file. Try again later. You can use -n to skip updating\n";
			exit;
		}
	} else {
		print " ( up-to-date )\n";
	}
} else {
	print " ( no version check )\n";
}

print "Verbose mode ON\n" if ($opt{v});
#
# Parsing CSV File
#
print "Reading input files. " if ($opt{v});
open(INPUT, $opt{i}) or die ("Can not read from file $opt{i}.");
while(<INPUT>) {
	chomp;
	if ( length($_) ) {
		if ( $_ =~ /(\d*\.\d*\.\d*\.\d*)/ ) {
			push(@targets, $1);
		}
	}
}
@targets = uniq(@targets);
close(INPUT);
print "[ ".scalar @targets ." IPs parsed ]\n" if ($opt{v});

my @fileOutput;
my @completed :shared;

#
# Main Loop
#
# Beware, dragons beneath here! Go away.
#
# Get the Password from STDIN 
#
$opt{p} = read_password('Enter your password : ') unless ($opt{p});
print "Fetching information from ".scalar @targets." IPs.\n" if ($opt{v});
$opt{t} = $MAXTHREADS	if ($opt{t} > $MAXTHREADS);
print "Running on ".$opt{t}." threads.\n";

my @running = ();
my @Threads;


my $i = 0;
my $fh;
open($fh, "> ".$opt{o}.".csv") or die ("Can not write on $opt{o}.");
print $fh "\"CI Name\";\"IP Address\";\"Slot\";\"Card\";\"Port\";\"SFP Type\";\"SFP Vendor\";\"Bandwidth\";\"State\";\"Description\"";
print $fh "\n";

my @DATA :shared;
my @STDOUT;
my %nodes :shared;
my %fill :shared;
my @uptimes :shared;
our %obj;
our $swirlCount :shared = 1;
our $swirlTime  :shared = time();

my %edges :shared;

my $graph = Graph::Easy->new();

while ( $i <= scalar @targets ) {
	@running = threads->list(threads::running);
	while ( scalar @running < $opt{t} ) {
		# print "New Thread on Item #$i\n";
		my $thread = threads->new( sub { &fetchDataFromNetwork( $targets[$i] );});
		push (@Threads, $thread);
		@running = threads->list(threads::running);
		$i++;
		if ( $i >= scalar @targets ) {
			last;
		}
	}
	
	sleep 1;
	foreach my $thr (@Threads) {
		if ($thr->is_joinable()) {
			$thr->join;
		}
	}
	
	last unless ($targets[$i]);
}

@running = threads->list(threads::running);
print "Waiting for ".scalar @running." pending threads.\n"  if ($opt{v});
while (scalar @running > 0) {
	foreach my $thr (@Threads) {
		if ($thr->is_joinable()) {
			$thr->join;
		}
	}
	@running = threads->list(threads::running);
}	
print "\n";

# Dump the data to CSV file that has been collected from Network
foreach my $dataLine (@DATA) {
	print $fh $dataLine;
}
close($fh);


my $graphFilename = "GRAPH_".$opt{o}.".html";
if ( $opt{g} ) {
	print "Generating graph.\n"  if($opt{v});
	# Generating graph file
	print "Nodes : ["  if($opt{v});

	my $minimum = min(@uptimes);
	my $tmpMax = stddev(@uptimes);
	my @newUptimes;
	foreach my $tmpUptime (@uptimes) {
		if ($tmpUptime <= $tmpMax) {
			push(@newUptimes, $tmpUptime);
		}
	}
	my $maximum = stddev(@newUptimes);
	# print "OLD STDDEV : $tmpMax\tNEW STDDEV : $maximum\n";
	my $ringLeader = 3;
	
	foreach my $key (sort keys %nodes) {
		my @edgestome = grep /-$key$/, keys %edges;
		my @edgesfromme = grep /^$key-/, keys %edges;
		my $myEdgeCount = (scalar @edgestome)+(scalar @edgesfromme);
		my $node = $graph->add_node(''.$key.'');
		my $namingSuffix = "";
		my $namingPrefix = "";
		
		# Check for the Ringleader
		if ( $myEdgeCount >= $ringLeader ) {
			$namingSuffix = " **";
			$node->set_attribute('borderstyle', 'bold-dash');
		} else {
			$node->set_attribute('shape', 'rounded');
		}
		
		# Check for the UPS Existance
		my $index;
		my $myCiName;
		for(my $x=0;$x <= $#targets;$x++) {
			# print "TARGET : $targets[$x] <=> $key\n";
			if ( $key eq $targets[$x] ) {
				$myCiName = $ciNames[$x];
				#print "INDEX ($key = $targets[$x]): $x\n";
				#print "CIName ($key): $myCiName (".in_array(\@upslist, $myCiName).")\n";
				$namingPrefix = "(U) " if ( in_array(\@upslist, $myCiName) );
				last;
			}
		}
		
		# Add prefix and suffix on the labeling
		$node->set_attribute('label', ''.$namingPrefix.$key.$namingSuffix.'');
		
		# $node->set_attribute('fill', $fill{$key}) if ($fill{$key});
		$node->set_attribute('font', 'Arial');
		
		# Finding the correct Percentage
		if ( $nodes{$key} >= $minimum && $nodes{$key} <= $maximum ) {
			# print "Percentage for $key ($nodes{$key}) is ".gradient($minimum, $maximum, $nodes{$key})."\n";
			$node->set_attribute('fill', '#'.gradient($minimum, $maximum, $nodes{$key}));
		} else {
			if ( $nodes{$key} > $tmpMax ) {
				$node->set_attribute('fill', '#7EE8ED');
			} elsif ( $nodes{$key} > $maximum ) {
				$node->set_attribute('fill', '#5B7AD9');
			}
			# print "Skipping $key ($nodes{$key}) out of boundaries ( $minimum <=> $maximum ). Gradient might be : ".gradient($minimum, $maximum, $nodes{$key})."\n";
		}
		
		$node->set_attribute('fontsize', '80%');
		
		if ( $links{$key} ) {
			$node->set_attribute('linkbase', '/');
			$node->set_attribute('autolink', 'name');
			$node->set_attribute('link', $links{$key});
		}
		print "."  if($opt{v});
	}
	print "]\n"  if($opt{v});



	print "Connections : ["  if($opt{v});
	foreach my $key (sort keys %edges) {
		my ($source, $destination) = split(/-/, $key);
		my $edge = $graph->add_edge(''.$source.'',''.$destination.'');
		$edge->set_attribute('arrowstyle', 'none');
		print "."  if($opt{v});
	}
	print "]\n" if($opt{v});

	$graph->output_format('svg');


	$graph->timeout(600);
	$graph->catch_warnings(1);					# Disable warnings
	
	if ( scalar @uptimes <= 200 ) {
		print "Re-organizing the graph"  if($opt{v});
		my $max = undef;

		$graph->randomize();
		my $seed = $graph->seed(); 

		$graph->layout();
		$max = $graph->score();

		for (1..10) {
		  $graph->randomize();                  # select random seed
		  $graph->layout();                     # layout with that seed
		  if ($graph->score() > $max) {
			$max = $graph->score();             # store the new max store
			$seed = $graph->seed();             # and it's seed
			print "." if ($opt{v});
			}
		 }

		# redo the best layout
		if ($seed ne $graph->seed()) {
		  $graph->seed($seed);
		  $graph->layout();
		  print "." if ($opt{v});
		 }
		 print "\n"  if ($opt{v});
	}

	print "Creating graph.\n"  if($opt{v});
	 

	open(GRAPHFILE, "> ".$graphFilename) or die("Can not create graphic file ".$graphFilename);
	print GRAPHFILE $graph->output();
	close(GRAPHFILE);
}

print "\nAll done and saved on $opt{o} ";
print "and $graphFilename." if ($opt{g});
print "\n";
print "Process took ".(time()-$time)." seconds with $opt{t} threads.\n"   if($opt{v});

#
# Related Functions
#
sub swirl() {
	
	my $diff = 1;
	my $now = time();	
	
	if ( ( $now - $swirlTime ) gt 1 ) {
		if    ( $swirlCount%8 eq 0 ) 	{ print "\b|"; $swirlCount++; }
		elsif ( $swirlCount%8 eq 1 ) 	{ print "\b/"; $swirlCount++; }
		elsif ( $swirlCount%8 eq 2 ) 	{ print "\b-"; $swirlCount++; }
		elsif ( $swirlCount%8 eq 3 ) 	{ print "\b\\"; $swirlCount++; }
		elsif ( $swirlCount%8 eq 4 ) 	{ print "\b|"; $swirlCount++; }
		elsif ( $swirlCount%8 eq 5 ) 	{ print "\b/"; $swirlCount++; }
		elsif ( $swirlCount%8 eq 6 ) 	{ print "\b-"; $swirlCount++; }
		elsif ( $swirlCount%8 eq 7 ) 	{ print "\b\\"; $swirlCount++; }

		$swirlTime = $now;
	}
	return;
	
}

sub fetchDataFromNetwork() {
	my $IP = shift;
	
	if($opt{v}) {
		$STDOUT[$i] = "[".($i+1)."] -> $targets[$i] : ";
	} else {
		$STDOUT[$i] = ".";
	}
	
	$obj{$IP} = new Net::Telnet ( Timeout => 240 );		# Do not forget to change timeout on new development !!!!!!!!!		
	$obj{$IP}->errmode("return");
	if ($obj{$IP}->open($IP)) {
		$STDOUT[$i] .= "C" if($opt{v});
		my $vendor = authenticate( $IP, \%opt );
		$STDOUT[$i] .= "A" if($opt{v});
		if ( $vendor ) { 
			my $prompt;
			my %interfaceTypes;
			my @regex;
			my $type10, $type1, $ciName;
			if ( $vendor eq 'cisco' ) {
				$STDOUT[$i] .= "(Cisco) " if($opt{v});
				$prompt = '/#$/';
				$type1 = '(Gi\d*\/(\d*)\/(\d*)\/(\d*))\s+';
				$type10 = '(Te\d*\/(\d*)\/(\d*)\/(\d*))\s+';
				$command[0] = 'sh int des';
				$command[1] = 'sh int des';
				$regex[1] = '_INTERFACE_\s*([updown\-ami]+)\s*[updown\-ami]+\s*(.*)';
				$ciName = runRemoteCommand($obj{$IP}, 'sh ver | i uptime', $prompt, '(.*) uptime is .*');
				$command[2] = 'show controllers _INTERFACE_ phy';
				$regex[2] = '\s*Xcvr Code: (.*)';
				$regex[3] = '\s*Vendor Name: (.*)';
			} elsif ( $vendor eq 'huawei' ) {
				$STDOUT[$i] .= "(Huawei)" if($opt{v});
				$prompt = '/<.*>$/';
				$type1  = '(GigabitEthernet(\d*)\/(\d*)\/(\d*))\s+';
				$type10 = '(GigabitEthernet(\d*)\/(\d*)\/(\d*))\(10G\)\s+';
				$command[0] = 'dis int b';
				$command[1] = 'dis int des';
				$regex[1] = 'GE_SLOT_\/_CARD_\/_PORT_\s*([\*updown]+)\s*[\*updown]+\s*(.*)';
				$ciName = runRemoteCommand($obj{$IP}, 'disp cur | i sysname', $prompt, 'sysname (.*)');
				$command[2] = 'disp int _INTERFACE_';
				$regex[2] = '\s*WaveLength: \d*nm, Transmission Distance: (.*)';
				$regex[3] = '\s*The Vendor Name is (.*)';
			}
			
			$STDOUT[$i] .= "[$ciName] " if($opt{v});
			
			# Fetch port allocations
			my @interfaces;
			my @return = $obj{$IP}->cmd(String => $command[0], Prompt => $prompt);
			my %ports;
			my %bandwidths;
			my %descriptions;
			my $slotCount, $cardCount, $gigPortCount, $tenGigPortCount = 0;
			foreach my $line ( @return ) {
				chomp($line);
				if ($line =~ /$type10/) {
					$ports{$2}{$3}{$4} = $1;
					$bandwidths{$2}{$3}{$4} = 10;
					$tenGigPortCount++;
					print "[$IP ".$tenGigPortCount."x10G] $1 ==> Slot: $2\tCard: $3\tPort: $4 (10G)\n" if ($opt{debug});
				} elsif ($line =~ /$type1/) {
					$ports{$2}{$3}{$4} = $1;
					$bandwidths{$2}{$3}{$4} = 1;
					$gigPortCount++;
					print "[$IP ".$gigPortCount."x1G] $1 ==> Slot: $2\tCard: $3\tPort: $4 (1G)\n" if ($opt{debug});
				} else {
					# print "[$IP} $line ==> IGNORED\n";
				}				
			}
			
			$gigPortCount--;
			
			# Fetch descriptions of related ports
			my @return = $obj{$IP}->cmd(String => $command[1], Prompt => $prompt);
			
			foreach my $line ( @return ) {	
				chomp($line);
				foreach my $slot ( sort(keys %ports) ) {
					# print "[IP] DUMP: /SLOT : $slot\n" if ($opt{debug});
					foreach my $card ( sort(keys %{$ports{$slot}}) ) {
						# print "[IP} DUMP: /SLOT/CARD : $card\n" if ($opt{debug});
						foreach my $port ( sort(keys %{${$ports{$slot}}{$card}}) ) {
							if ( !in_array(\@ignoreList, ${$ports{$slot}{$card}}{$port}) ) { 
								my $check = ${$ports{$slot}{$card}}{$port};
								my $checkReg = $regex[1];
								$checkReg =~ s/_INTERFACE_/$check/g;
								$checkReg =~ s/_SLOT_/$slot/g;
								$checkReg =~ s/_CARD_/$card/g;
								$checkReg =~ s/_PORT_/$port/g;
								&swirl();
								# print "[IP] REGEX : $checkReg on $line\n";
								if ( $line =~ /$checkReg/ ) {
									my $state = $1;
									my $description = $2;
									# print "[IP] LINE : (".$command[1].") $line\n";
									# print "[IP] DUMP: /SLOT/CARD/PORT : $port is ".${$ports{$slot}{$card}}{$port}." (".${$bandwidths{$slot}{$card}}{$port}."G) : $state ==> $description\n" if ($opt{debug});
									$DATA[$i] .= "\"".$ciName."\";\"".$IP."\";\"".$slot."\";\"".$card."\";\"".$port."\";";
									my $cmd = $command[2];
									my $change = ${$ports{$slot}{$card}}{$port};
									$cmd =~ s/_INTERFACE_/$change/g;
									
									my @return = $obj{$IP}->cmd(String => $cmd, Prompt => $prompt) or die($obj{$IP}->errmsg);
									my $SFPType, $SFP;
									my $SFPTypeRegex = $regex[2];
									my $SFPRegex = $regex[3];
									
									foreach my $line (@return) {
										# print "[$IP] DEBUG LINE : $line";
										if ( $line =~ /$SFPTypeRegex/ ) {
											print "Match Regex : $1\n" if ( $opt{debug} );
											$SFPType = $1;
										} elsif ( $line =~ /$SFPRegex/ ) {
											print "Match Regex : $1\n" if ( $opt{debug} );
											$SFP = $1;
										}
									}
							
									print "[$IP] SFP on $change : $SFPType ( $SFP )\n" if ( $opt{debug} );
									$DATA[$i] .= "\"".$SFPType."\";"; undef $SFPType;
									$DATA[$i] .= "\"".$SFP."\";"; undef $SFP; undef $SFPRegex;
									$DATA[$i] .= "\"".${$bandwidths{$slot}{$card}}{$port}."G\";\"".$state."\";\"".$description."\"\n";
								}
							} else {
								print "[IP] Skipping ${$ports{$slot}{$card}}{$port} as it is in my ignore list.\n" if ($opt{debug});
							}
						}
					}
				}
			}
						
			$STDOUT[$i] .= "[ ".($tenGigPortCount + $gigPortCount)." ports ( ".$gigPortCount."x1G + ".$tenGigPortCount."x10G ) ] " if ($opt{v});
			
		} else {
			$STDOUT[$i] .= " (Username/Password Problem) " if ($opt{v});
		}
		disconnect($IP);
		$STDOUT[$i] .= "D"  if ($opt{v});
	} else {
		$STDOUT[$i] .= "Could not initiate a TCP Session on port 23";
	}
	
	print "\b".$STDOUT[$i];
	print "\n" if ($opt{v});
	
	return;
}

sub disconnect() {
	my $IP			= shift;
	
	$obj{$IP}->close();
	return 1;
}

sub authenticate() {
	my $targetIP = shift;
	my $opt = shift;
	
	my @initialCommands;
	my $vendor;
	my @prompt;
	my $timeOut = 5;
	
	if ($obj{$targetIP}->login( Name => $opt{u}, Password => $opt{p}, Prompt => '/#$/', Timeout => $timeOut ) ) {			# Try for Cisco
		print "Logged in Cisco!\n" if ($opt{debug});
		$vendor = "cisco";
		$initialCommands[0] = "terminal length 0";
		$prompt[0] = '/#$/';
	} else {
		print "Cisco login failed. Trying huawei\n" if ( $opt{debug} );
		# print "." unless ($opt{debug});
		$obj{$targetIP}->close();
		delete $obj{$targetIP};
		$obj{$targetIP} = new Net::Telnet ( Timeout => 240 ); #, Input_Log => "input.log" ); # , Option_log => "option.log", Dump_Log => "dump.log", Input_Log => "input.log");
		$obj{$targetIP}->errmode("return");	
		$obj{$targetIP}->open($targetIP);
		
		
		#
		# RFC 1037 Hack for stupid Huawei Telnet Service forcing us to use 80 chars width
		$obj{$targetIP}->option_callback(sub { return; });
        $obj{$targetIP}->option_accept(Do => 31);
		
		$obj{$targetIP}->telnetmode(0);
        $obj{$targetIP}->put(pack("C9",
		              255,					# TELNET_IAC
		              250,					# TELNET_SB
		              31, 0, 500, 0, 0,		# TELOPT_NAWS
		              255,					# TELNET_IAC
		              240));				# TELNET_SE
        $obj{$targetIP}->telnetmode(1);	
		# idiots..
		#
		
		# print "." unless ($opt{debug});
		if($obj{$targetIP}->login( Name => $opt{u}, Password => $opt{p}, Prompt => '/<.*>$/', Timeout => $timeOut ) ) { 	# Try for Huawei
			print "Logged in Huawei!\n" if ($opt{debug});
			$vendor = "huawei";
			$initialCommands[0] = "system-view";
			$prompt[0] = '/]$/';
			$initialCommands[1] = "screen-width 512";
			$prompt[1] = '/]:$/';
			$initialCommands[2] = "Y";
			$prompt[2] = '/]$/';
			$initialCommands[3] = "quit";
			$prompt[3] = '/<.*>$/';
			$initialCommands[4] = "screen-length 0 temporary";
			$prompt[4] = '/<.*>$/';
		} else {
			return 0;
		}
	}
	
	# Fixing screen buffering problems
	for(my $i=0;$i < scalar(@initialCommands);$i++) {
		print "Running '$initialCommands[$i]' with prompt $prompt[$i] : " if ($opt{debug});
		$obj{$targetIP}->cmd(String => $initialCommands[$i], Prompt => $prompt[$i]);
		print "Ok!\n" if ($opt{debug});
	}		
	return $vendor;
}

sub runRemoteCommand( $ $ $ $ ) {
	my $object = shift;
	my $cmd = shift;
	my $prompt = shift;
	my $regex = shift;
	
	print "Running CMD : $cmd with prompt $prompt ( filter with : $regex )\n"  if ( $opt{debug} );
	my @return = $object->cmd(String => $cmd, Prompt => $prompt) or die($object->errmsg);
	foreach my $line (@return) {
		# print "RETURN LINE : $line";
		if ( $line =~ /$regex/ ) {
			print "Match Regex : $1\n" if ( $opt{debug} );
			return $1;
		}
	}	
}

sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}

sub gradient {
    my $min = shift;
	my $max = shift;
	my $num = shift;
	
    my $middle = ( $min + $max ) / 2;
    my $scale = 255 / ( $middle - $min );

    return "FF0000" if $num <= $min;    # lower boundry
    return "00FF00" if $num >= $max;    # upper boundary

    if ( $num < $middle ) {
        return sprintf "FF%02X00" => int( ( $num - $min ) * $scale );
    } else {
        return sprintf "%02XFF00" => 255 - int( ( $num - $middle ) * $scale );
    }
}

sub in_array {
     my ($arr,$search_for) = @_;
     my %items = map {$_ => 1} @$arr; 
     return (exists($items{$search_for}))?1:0;
}
 
sub usage {
		my $usageText = << 'EOF';
	
This script finds and reports physical entities like slot, card and  port on given list of NEs.

Author            Emre Erkunt
                  (emre.erkunt@superonline.net)

Usage : slotCarPortCapacity [-i INPUT FILE] [-o OUTPUT FILE] [-v] [-u USERNAME] [-p PASSWORD] [-t THREAD COUNT] [-g] [-n]

Example INPUT FILE format is ;
------------------------------
172.28.191.196
172.28.191.194
172.28.191.193
------------------------------

 Parameter Descriptions :
 -i [INPUT FILE]        Input file that includes IP addresses
 -o [OUTPUT FILE]       Output file about results
 -u [USERNAME]          Given Username to connect NEs
 -p [PASSWORD]          Given Password to connect NEs
 -n                     Skip self-updating
 -t [THREAD COUNT]      Number of threads that should run in parallel      ( Default 2 threads )
 -g                     Generate network graph                             ( Default OFF )
 -v                     Disable verbose                                    ( Default ON )

EOF
		print $usageText;
		exit;
}   # usage()

sub interrupt {
    print STDERR "Stopping! Be patient!\n";
	exit 0;
}