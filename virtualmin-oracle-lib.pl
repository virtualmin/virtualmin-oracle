# Functions for the Oracle database
use strict;
use warnings;
our (%text, %in, %config);
our $module_name;
our $module_config_directory;
our ($tb, $cb);
our $done_remote_require;
our $remote_user;

BEGIN { push(@INC, ".."); };
eval "use WebminCore;";
&init_config();
&foreign_require("virtual-server", "virtual-server-lib.pl");
our %access = &get_module_acl();

our $sqlplus_cmd = "$config{'oracle_home'}/bin/sqlplus";
our $init_template = $config{'init'} =~ /^\// ? $config{'init'} :
			"$config{'oracle_home'}/$config{'init'}";
our $tnsnames_file = $config{'tnsnames'} =~ /^\// ? $config{'tnsnames'} :
			"$config{'oracle_home'}/$config{'tnsnames'}";
our @type_list = ( "varchar2", "char", "number", "date", "long", "raw", "clob", "blob" );

our $default_dbs_file = "$module_config_directory/defdbs";

# check_config()
# Returns an error message if the config doesn't look OK
sub check_config
{
if ($config{'remote'}) {
	return &remote_oracle_call("check_config");
	}
if ($config{'host'}) {
	# Connecting to a remote host, so we don't need a lot of these checks
	&to_ipaddress($config{'host'}) ||
		&text('check_ehost', "<tt>$config{'host'}</tt>");
	return undef;
	}
if (!-d $config{'oracle_home'} || !-x $sqlplus_cmd) {
	return &text('check_ehome', "<tt>$config{'oracle_home'}</tt>");
	}
elsif (!defined(getpwnam($config{'unix'}))) {
	return $text{'check_eunix'};
	}
elsif (!-d $config{'dir'}) {
	return &text('check_edir', "<tt>$config{'dir'}</tt>");
	}
elsif (!-r $init_template) {
	return &text('check_einit', "<tt>$config{'init'}</tt>");
	}
else {
	# Check for needed Perl modules
	foreach my $m ("DBI", "DBD::Oracle") {
		eval "use $m";
		if ($@) {
			my $err = &text('check_emod', $m);
			if (&foreign_available("cpan")) {
				$err .= &text('check_ecpan',
				    "../cpan/download.cgi?source=3&cpan=$m");
				}
			return $err;
			}
		}

	# Attempt a test command
	my ($ok, $out) = &execute_oracle_sql($config{'sid'},
					"select sysdate from sys.dual;");
	if (!$ok) {
		return &text('check_elogin', "<pre>$out</pre>");
		}
	}
return undef;
}

# execute_oracle_sql(sid, command, [&domain-as])
# Runs SQLplus to execute some Oracle command, and returns an ok/failed flag
# and the output.
sub execute_oracle_sql
{
my ($sid, $sql, $d) = @_;
if ($config{'remote'}) {
	return &remote_oracle_call("execute_oracle_sql", $sid, $sql, $d);
	}
$ENV{'ORACLE_SID'} = $sid;
$ENV{'ORACLE_HOME'} = $config{'oracle_home'};
my $temp = &transname();
open(my $TEMP, ">", "$temp");
print $TEMP $sql,"\n";
close($TEMP);
my $cmd;
if ($d) {
	$cmd = "$sqlplus_cmd ".quotemeta("$d->{'user'}/$d->{'pass'}");
	}
else {
	$cmd = "$sqlplus_cmd ".quotemeta("$config{'user'}/$config{'pass'}").
	       " as sysdba";
	}
$cmd = &command_as_user($config{'unix'}, 0, $cmd);
my $out;
no strict "subs";
&open_execute_command(OUT, "$cmd 2>&1 <$temp", 1);
while(<OUT>) {
	$out .= $_;
	}
my $ex = close(OUT);
use strict "subs";
$out =~ s/\r//g;
$out =~ s/SQL>\s+Disconnected[\000-\377]*$//;
if ($out =~ /ERROR\s+at\s+line\s+\d+/) {
	$out =~ s/^[\000-\377]*ERROR\s+at\s+line\s+\d+.*\n//;
	return (0, $out);
	}
elsif ($out =~ /(ORA-(\d+):\s+.*)/) {
	return (0, $1);
	}
else {
	$out =~ s/^([\000-\377]*)?SQL>.*\n//;
	return (1, $out);
	}
}

# execute_oracle_sql_error(sid, command)
# Attempts to execute some SQL, or calls error on failure
sub execute_oracle_sql_error
{
my ($ok, $out) = &execute_oracle_sql(@_);
$ok || &error("<tt>$_[1]</tt> failed : <tt>$out</tt>");
return ($ok, $out);
}

# execute_sql(sid, command, [param, ...])
# Executes some SQL query via DBI, and returns the headers and data. Calls
# &error upon failure.
sub execute_sql
{
my ($db, $cmd, @params) = @_;
if ($config{'remote'}) {
	# Pass through to remote
	return &remote_oracle_call("execute_sql", $db, $cmd, @params);
	}


my $dbh = &get_dbi_handle($db);
$cmd = $dbh->prepare($cmd);
$cmd || &error(&text('index_esql', $cmd, $dbh->errstr));
my $rv;
($rv = $cmd->execute(@params)) || &error(&text('index_esql', $dbh->errstr));
my @data;
while(my @r = $cmd->fetchrow()) {
	push(@data, \@r);
	}
my @titles = @{$cmd->{'NAME'}};
$cmd->finish();
$dbh->commit();
$dbh->disconnect();
return { 'titles' => \@titles,
	 'data' => \@data,
	 'rows' => $rv };
}

# get_dbi_handle(db)
# Returns the DBI handle for some database
sub get_dbi_handle
{
$ENV{'ORACLE_HOME'} = $config{'oracle_home'};
use DBI;
my $drh;
eval '$drh = DBI->install_driver("Oracle")';
if ($@) {
	&error($@);
	}
my ($user, $pass);
if ($access{'user'}) {
	$user = $access{'user'};
	$pass = $access{'pass'};
	}
else {
	$user = $config{'user'};
	$pass = $config{'pass'};
	}
my $cstr = $config{'host'} ? "host=$config{'host'};sid=$db" : $db;
my $dbh = $drh->connect($cstr, $user, $pass, { });
$dbh || &error(&text('index_eopen', $drh->errstr));
return $dbh;
}

# create_oracle_database(&domain, dbname)
# Creates a single Oracle database from scratch, calling print commands
sub create_oracle_database
{
my ($d, $dbname) = @_;

if ($config{'remote'}) {
	# Call on remote
	&first_print(&text('create_remote', $config{'remote'}));
	my $rv = &remote_oracle_call("create_oracle_database", $d, $dbname);
	if ($rv) {
		# Add to DB list in local domain object
		&second_print($virtual_server::text{'setup_done'});
		my @dbs = split(/\s+/, $d->{'db_'.$module_name});
		push(@dbs, $dbname);
		$d->{'db_'.$module_name} = join(" ", @dbs);
		}
	else {
		&second_print($text{'create_remoteerr'});
		}
	return $rv;
	}

# Copy init.ora into place
&first_print(&text('create_init', "init$dbname.ora"));
my $init_new = &init_ora_dir()."/init$dbname.ora";
my $out;
my $ex = &execute_command(&command_as_user($config{'unix'}, 0,
	"cp ".quotemeta($init_template)." ".quotemeta($init_new)),
	undef, \$out, \$out);
if ($ex) {
	&second_print(&text('create_failed', "<tt>$out</tt>"));
	return 0;
	}

# Edit file to use correct new parameters
my $lref = &read_file_lines($init_new);
my %done;
foreach my $l (@$lref) {
	if ($l =~ /^(\s*#)?\s*db_name\s*=/ &&
	    !$done{'db_name'}++) {
		$l = "db_name=$dbname";
		}
	elsif ($l =~ /^(\s*#)?\s*shared_pool_size\s*=/ &&
	       !$done{'shared_pool_size'}++) {
		$l = "shared_pool_size=$config{'pool'}";
		}
	elsif ($l =~ /^(\s*#)?\s*control_files\s*=/ &&
	       !$done{'control_files'}++) {
		$l = "control_files = (${dbname}_control1, ${dbname}_control2)";
		}
	elsif ($l =~ /^(\s*#)?\s*rollback_segments\s*=/ &&
	       !$done{'rollback_segments'}) {
		$l = "rollback_segments = (${dbname}1, ${dbname}2)";
		}
	}
&flush_file_lines($init_new);
&second_print($virtual_server::text{'setup_done'});

# Startup the database in nomount mode
&first_print(&text('create_startup', $dbname));
my $ok;
($ok, $out) = &execute_oracle_sql($dbname, "startup nomount");
if (!$ok) {
	&second_print(&text('create_failed',
					     "<pre>$out</pre>"));
	return 0;
	}
else {
	&second_print($virtual_server::text{'setup_done'});
	}

# Create the database
&first_print($text{'create_create'});
($ok, $out) = &execute_oracle_sql($dbname,
"create database $dbname
	datafile '$config{'dir'}/${dbname}.dbs' size $config{'dbsize'}
	autoextend on next 10M maxsize unlimited
logfile group 1 '$config{'dir'}/${dbname}1.rdo' size $config{'logsize'} ,
	group 2 '$config{'dir'}/${dbname}2.rdo' size $config{'logsize'}
sysaux datafile '$config{'dir'}/${dbname}aux.dbs' size $config{'auxsize'}
	autoextend on next 10M maxsize unlimited
default temporary tablespace temp tempfile '$config{'dir'}/${dbname}temp.dbs' size $config{'tempsize'};
	");
if (!$ok) {
	&second_print(&text('create_failed',
					     "<pre>$out</pre>"));
	return 0;
	}
else {
	&second_print($virtual_server::text{'setup_done'});
	}

# Add rollback segment?
if ($config{'rollbacksize'}) {
	&first_print($text{'create_rollback'});
	my ($ok, $out) = &execute_oracle_sql($dbname, "create rollback segment ${dbname}rbs storage ($config{'rollbacksize'} autoextend on next 10M maxsize unlimited);");
	if (!$ok) {
		&second_print(&text('create_failed',
						     "<pre>$out</pre>"));
		}
	else {
		&second_print($virtual_server::text{'setup_done'});
		}
	}

# Create the catalog
if ($config{'catalog'}) {
	&first_print($text{'create_catalog'});
	my ($ok, $out) = &execute_oracle_sql($dbname, "\@?/rdbms/admin/catalog.sql");
	&second_print($virtual_server::text{'setup_done'});
	}

# Create procedures
if ($config{'catproc'}) {
	&first_print($text{'create_catproc'});
	my ($ok, $out) = &execute_oracle_sql($dbname, "\@?/rdbms/admin/catproc.sql");
	&second_print($virtual_server::text{'setup_done'});
	}

# Create product user profile
if ($config{'pupbld'}) {
	&first_print($text{'create_pupbld'});
	my ($ok, $out) = &execute_oracle_sql($dbname, "\@?/sqlplus/admin/pupbld.sql");
	&second_print($virtual_server::text{'setup_done'});
	}

# Create and grant users
foreach my $u ([ $d->{'user'}, $d->{'pass'} ],
	       [ $config{'user'}, $config{'pass'} ]) {
	&first_print(&text('create_user', $u->[0]));
	my ($ok, $out) = &execute_oracle_sql($dbname, "create user $u->[0] identified by \"$u->[1]\";");
	if (!$ok) {
		&second_print(&text('create_failed', "<pre>$out</pre>"));
		return 0;
		}
	($ok, $out) = &execute_oracle_sql($dbname, "grant all privileges to $u->[0];");
	if (!$ok) {
		&second_print(&text('create_failed', "<pre>$out</pre>"));
		return 0;
		}
	&second_print($virtual_server::text{'setup_done'});
	}

# Add to tnsnames.ora
&first_print($text{'create_tnsnames'});
$lref = &read_file_lines($tnsnames_file);
push(@$lref,
	"$dbname = ",
	"  (DESCRIPTION =",
	"    (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1521))",
	"    (CONNECT_DATA =",
	"      (SERVER = DEDICATED)",
	"      (SERVICE_NAME = $dbname)",
	"    )",
	"  )");
&flush_file_lines($tnsnames_file);
&second_print($virtual_server::text{'setup_done'});

# Add to DB list for this server
my @dbs = split(/\s+/, $d->{'db_'.$module_name});
push(@dbs, $dbname);
$d->{'db_'.$module_name} = join(" ", @dbs);

return 1;
}

# delete_oracle_database(&domain, dbname)
# Delete all files used by some oracle DB
sub delete_oracle_database
{
my ($d, $dbname) = @_;

if ($config{'remote'}) {
	# Call on remote
	&first_print(&text('delete_remote', $config{'remote'}));
	my $rv = &remote_oracle_call("delete_oracle_database", $d, $dbname);
	if ($rv) {
		# Delete from DB list in local domain object
		&second_print($virtual_server::text{'setup_done'});
		my @dbs = split(/\s+/, $d->{'db_'.$module_name});
		@dbs = grep { $_ ne $dbname } @dbs;
		$d->{'db_'.$module_name} = join(" ", @dbs);
		}
	else {
		&second_print($text{'create_remoteerr'});
		}
	return $rv;
	}

# Shut down the DB
my @files = &oracle_database_files($dbname);
&first_print(&text('delete_shutdown', $dbname));
my ($ok, $out) = &execute_oracle_sql($dbname, "shutdown immediate;");
if (!$ok && $out =~ /ORA-01034/) {
	&second_print($text{'delete_down'});
	}
elsif (!$ok) {
	&second_print(&text('create_failed',
					     "<pre>$out</pre>"));
	return 0;
	}
else {
	&second_print($virtual_server::text{'setup_done'});
	}

# Delete all the data and .ora files
&first_print($text{'delete_files'});
foreach my $f (@files) {
	unlink($f->[0]);
	}
my $init_new = &init_ora_dir()."/init$dbname.ora";
unlink($init_new);
&second_print($virtual_server::text{'setup_done'});

# Delete from tnsnames.ora
&first_print($text{'delete_tnsnames'});
my $lref = &read_file_lines($tnsnames_file);
my ($start, $end, $indent);
for(my $i=0; $i<@$lref; $i++) {
	if ($lref->[$i] =~ /^$dbname\s*=/) {
		$start = $i;
		}
	if (defined($start)) {
		$indent += ($lref->[$i] =~ tr/\(/\(/);
		$indent -= ($lref->[$i] =~ tr/\)/\)/);
		if ($lref->[$i] =~ /\)/ && $indent == 0) {
			$end = $i;
			last;
			}
		}
	}
if (defined($start) && defined($end)) {
	splice(@$lref, $start, $end-$start+1);
	&second_print($virtual_server::text{'setup_done'});
	}
else {
	&second_print($text{'delete_not'});
	}
&flush_file_lines($tnsnames_file);

# Remove DB list for this server
my @dbs = split(/\s+/, $d->{'db_'.$module_name});
@dbs = grep { $_ ne $dbname } @dbs;
$d->{'db_'.$module_name} = join(" ", @dbs);

return 1;
}

# modify_oracle_database(&domain, dbname)
# Sets a user's password in a database
sub modify_oracle_database
{
my ($d, $dbname) = @_;
&first_print(&text('modify_pass', $dbname));
my ($ok, $out) = &execute_oracle_sql($dbname, "alter user $d->{'user'} identified by \"$d->{'pass'}\";");
if (!$ok) {
	&second_print(&text('create_failed',
					     "<pre>$out</pre>"));
	return 0;
	}
else {
	&second_print($virtual_server::text{'setup_done'});
	return 1;
	}
}

sub init_ora_dir
{
$init_template =~ /^(.*)\//;
return $1;
}

sub oracle_dbname
{
if (length($_[0]) > 8) {
	return substr($_[0], 0, 8);
	}
else {
	return $_[0];
	}
}

# oracle_database_files(dbname)
# Returns a list of all files used by some Oracle DB for data and control
sub oracle_database_files
{
my ($dbname) = @_;
if ($config{'remote'}) {
	return &remote_oracle_call("oracle_database_files", $dbname);
	}

my @rv;
foreach my $cmd ('select name from V$DATAFILE;',
		 'select member from V$LOGFILE;',
		 'select value from v$parameter where name like \'log_archive_dest%\'',
		 'select name from v$controlfile;',
		 'select value from v$parameter where name like \'%dest\';',
		 ) {
	my ($ok, $out) = &execute_oracle_sql($dbname, $cmd);
	foreach my $l (split(/\r?\n/, $out)) {
		if ($l =~ /^\// && -r $l) {
			my @st = stat($l);
			push(@rv, [ $l, $st[7] ]);
			}
		}
	}
return @rv;
}

# list_tables(dbase)
sub list_tables
{
my ($db) = @_;
my $d = &execute_sql($db, "select table_name from user_tables");
return map { $_->[0] } @{$d->{'data'}};
}

sub can_edit_db
{
my ($db) = @_;
return 1 if ($access{'db'} eq '*');
my @dbs = split(/\t+/, $access{'db'});
return &indexof($db, @dbs) >= 0;
}

# show_table_form(count)
sub show_table_form
{
print "<table border>\n";
print "<tr $tb> <td><b>$text{'field_name'}</b></td> ",
      "<td><b>$text{'field_type'}</b></td> ",
      "<td><b>$text{'field_size'}</b></td> ",
      "<td><b>$text{'table_nkey'}</b></td> ",
      "<td><b>$text{'field_null'}</b></td> </tr>\n";
for(my $i=0; $i<$_[0]; $i++) {
	print "<tr $cb>\n";
	print "<td><input name=field_$i size=20></td>\n";
	print "<td><select name=type_$i>\n";
	print "<option selected>\n";
	foreach my $t (@type_list) {
		print "<option value='$t'>$t\n";
		}
	print "</select></td>\n";
	print "<td><input name=size_$i size=10></td>\n";
	print "<td><input type=checkbox name=key_$i value=1>&nbsp;",
	      "$text{'yes'}</td>\n";
	print "<td><input type=checkbox name=null_$i value=1 checked>&nbsp;",
	      "$text{'yes'}</td>\n";
	print "</tr>\n";
	}
print "</table>\n";
}

# parse_table_form(&extrafields, tablename)
sub parse_table_form
{
my @fields = @{$_[0]};
my (@auto, @pri);
for(my $i=0; defined($in{"field_$i"}); $i++) {
	next if (!$in{"field_$i"});
	$in{"field_$i"} =~ /^\S+$/ ||
		&error(&text('table_efield', $in{"field_$i"}));
	$in{"type_$i"} || &error(&text('table_etype', $in{"field_$i"}));
	if ($in{"type_$i"} eq 'char' || $in{"type_$i"} eq 'varchar' ||
	    $in{"type_$i"} eq 'varchar2') {
		$in{"size_$i"} || &error(&text('table_esize', $in{"field_$i"}));
		}
	if ($in{"type_$i"} eq 'enum' || $in{"type_$i"} eq 'set') {
		my @ev = split(/\s+/, $in{"size_$i"});
		@ev || &error(&text('table_eenum', $in{"type_$i"},
						   $in{"field_$i"}));
		$in{"size_$i"} = join(",", map { "'$_'" } @ev);
		}
	if ($in{"size_$i"}) {
		push(@fields, sprintf "%s %s(%s)",
		     &quotestr($in{"field_$i"}), $in{"type_$i"},$in{"size_$i"});
		}
	else {
		push(@fields, sprintf "%s %s",
			&quotestr($in{"field_$i"}), $in{"type_$i"});
		}
	if (!$in{"null_$i"}) {
		$fields[@fields-1] .= " not null";
		}
	if ($in{"key_$i"}) {
		$in{"null_$i"} && &error(&text('table_epnull',$in{"field_$i"}));
		push(@pri, $in{"field_$i"});
		}
	}
@fields || &error($text{'table_enone'});
my @sql;
my $sql = "create table ".&quotestr($_[1])." (".join(",", @fields).")";
$sql .= " type = $in{'type'}" if ($in{'type'});
push(@sql, $sql);
if (@pri) {
	# Setup primary fields too
	push(@sql, "alter table ".&quotestr($_[1])." add primary key (".
		    join(",", map { &quotestr($_) } @pri).")");
	}
return @sql;
}

sub quotestr
{
return $_[0];
#return "'$_[0]'";
}

# table_structure(db, table)
# Returns an array of field objects for this table
sub table_structure
{
my ($db, $table) = @_;
if ($config{'remote'}) {
	# Pass through to remote
	return &remote_oracle_call("table_structure", $db, $table);
	}

my $d = &execute_sql($db, "select * from $table where 0 = 1");
my $dbh = &get_dbi_handle($db);

# Get the table info
my $tbl = $dbh->table_info(undef, undef, $table, 'TABLE');
my $t = $tbl->fetchrow_hashref();
my $schema = $t->{'TABLE_SCHEM'};
$tbl->finish();

# Get primary keys
my $pri = $dbh->primary_key_info(undef, $schema, $table);
my %ispri;
while(my $p = $pri->fetchrow_hashref()) {
	$ispri{$p->{'COLUMN_NAME'}} = 'PRI';
	}
$pri->finish();

# Get the table structure
my @rv;
foreach my $c (@{$d->{'titles'}}) {
	my $info = $dbh->column_info(undef, undef, $table, $c);
	my $i = $info->fetchrow_hashref();
	push(@rv, { 'field' => $i->{'COLUMN_NAME'},
		    'type' => $i->{'TYPE_NAME'}."($i->{'COLUMN_SIZE'})",
		    'null' => $i->{'IS_NULLABLE'},
		    'key' => $ispri{$i->{'COLUMN_NAME'}} });
	$info->finish();
	}
$dbh->disconnect();
return @rv;
}

sub is_blob
{
return $_[0]->{'type'} =~ /(long|raw|blob)$/i;
}

# remote_oracle_call(func, args, ...)
# Calls some function on the configured remote Webmin server
sub remote_oracle_call
{
my ($func, @args) = @_;
if (!$done_remote_require) {
	# Do the require first
	&remote_foreign_require($config{'remote'}, $module_name,
				"virtualmin-oracle-lib.pl");
	my %rconfig = %config;
	delete($rconfig{'remote'});
	$rconfig{'remoted'} = 1;
	my $ser = &serialise_variable(\%rconfig);
	&remote_eval($config{'remote'}, "virtualmin_oracle",
	     "\$c = &unserialise_variable(\"$ser\"); \%config = \%\$c;");
	}
return &remote_foreign_call($config{'remote'}, $module_name, $func, @args);
}

# oracle_database_exists(name)
# Checks if some Oracle DB exists or not
sub oracle_database_exists
{
my ($dbname) = @_;
if ($config{'remote'}) {
	return &remote_oracle_call("oracle_database_exists", $dbname);
	}
else {
	return -r &init_ora_dir()."/init$dbname.ora";
	}
}

# database_names()
# Returns the names of all known Oracle DBs
sub list_oracle_database_names
{
if ($config{'remote'}) {
	# Get list from remote
	return &remote_oracle_call("list_oracle_database_names", $_[0]);
	}
else {
	my $dir = &init_ora_dir();
	my @rv;
	opendir(DIR, $dir);
	foreach my $f (readdir(DIR)) {
		if ($f =~ /^init(\S+).ora$/) {
			push(@rv, $1);
			}
		elsif ($f eq "init.ora") {
			# Assume default SID
			push(@rv, $config{'sid'});
			}
		}
	closedir(DIR);
	return @rv;
	}
}

sub first_print
{
if (!$config{'remoted'}) {
	&$virtual_server::first_print(@_);
	}
}

sub second_print
{
if (!$config{'remoted'}) {
	&$virtual_server::second_print(@_);
	}
}

sub get_default_db
{
my %defs;
&read_env_file($default_dbs_file, \%defs);
return $defs{$remote_user};
}

sub set_default_db
{
my %defs;
&read_env_file($default_dbs_file, \%defs);
$defs{$remote_user} = $_[0];
&write_env_file($default_dbs_file, \%defs);
}

1;
