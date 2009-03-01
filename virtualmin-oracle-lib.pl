# Functions for the Oracle database

BEGIN { push(@INC, ".."); };
eval "use WebminCore;";
if ($@) {
	do '../web-lib.pl';
	do '../ui-lib.pl';
	}
&init_config();
&foreign_require("virtual-server", "virtual-server-lib.pl");
%access = &get_module_acl();

$sqlplus_cmd = "$config{'oracle_home'}/bin/sqlplus";
$init_template = $config{'init'} =~ /^\// ? $config{'init'} :
			"$config{'oracle_home'}/$config{'init'}";
$tnsnames_file = $config{'tnsnames'} =~ /^\// ? $config{'tnsnames'} :
			"$config{'oracle_home'}/$config{'tnsnames'}";
@type_list = ( "varchar2", "char", "number", "date", "long", "raw", "clob", "blob" );

$default_dbs_file = "$module_config_directory/defdbs";

# check_config()
# Returns an error message if the config doesn't look OK
sub check_config
{
if ($config{'remote'}) {
	return &remote_oracle_call("check_config");
	}
if ($config{'host'}) {
	# Connecting to a remote host, so we don't need a lot of these checks
	gethostbyname($config{'host'}) ||
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
			local $err = &text('check_emod', $m);
			if (&foreign_available("cpan")) {
				$err .= &text('check_ecpan',
				    "../cpan/download.cgi?source=3&cpan=$m");
				}
			return $err;
			}
		}

	# Attempt a test command
	local ($ok, $out) = &execute_oracle_sql($config{'sid'},
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
local ($sid, $sql, $d) = @_;
if ($config{'remote'}) {
	return &remote_oracle_call("execute_oracle_sql", $sid, $sql, $d);
	}
$ENV{'ORACLE_SID'} = $sid;
$ENV{'ORACLE_HOME'} = $config{'oracle_home'};
local $temp = &transname();
open(TEMP, ">$temp");
print TEMP $sql,"\n";
close(TEMP);
local $cmd;
if ($d) {
	$cmd = "$sqlplus_cmd ".quotemeta("$d->{'user'}/$d->{'pass'}");
	}
else {
	$cmd = "$sqlplus_cmd ".quotemeta("$config{'user'}/$config{'pass'}").
	       " as sysdba";
	}
$cmd = &command_as_user($config{'unix'}, 0, $cmd);
local $out;
&open_execute_command(OUT, "$cmd 2>&1 <$temp", 1);
while(<OUT>) {
	$out .= $_;
	}
local $ex = close(OUT);
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
local ($ok, $out) = &execute_oracle_sql(@_);
$ok || &error("<tt>$_[1]</tt> failed : <tt>$out</tt>");
return ($ok, $out);
}

# execute_sql(sid, command, [param, ...])
# Executes some SQL query via DBI, and returns the headers and data. Calls 
# &error upon failure.
sub execute_sql
{
local ($db, $cmd, @params) = @_;
if ($config{'remote'}) {
	# Pass through to remote
	return &remote_oracle_call("execute_sql", $db, $cmd, @params);
	}


local $dbh = &get_dbi_handle($db);
local $cmd = $dbh->prepare($cmd);
$cmd || &error(&text('index_esql', $cmd, $dbh->errstr));
($rv = $cmd->execute(@params)) || &error(&text('index_esql', $dbh->errstr));
local @data;
while(my @r = $cmd->fetchrow()) {
	push(@data, \@r);
	}
local @titles = @{$cmd->{'NAME'}};
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
local $drh;
eval '$drh = DBI->install_driver("Oracle")';
if ($@) {
	&error($@);
	}
local ($user, $pass);
if ($access{'user'}) {
	$user = $access{'user'};
	$pass = $access{'pass'};
	}
else {
	$user = $config{'user'};
	$pass = $config{'pass'};
	}
local $cstr = $config{'host'} ? "host=$config{'host'};sid=$db" : $db;
local $dbh = $drh->connect($cstr, $user, $pass, { });
$dbh || &error(&text('index_eopen', $drh->errstr));
return $dbh;
}

# create_oracle_database(&domain, dbname)
# Creates a single Oracle database from scratch, calling print commands
sub create_oracle_database
{
local ($d, $dbname) = @_;

if ($config{'remote'}) {
	# Call on remote
	&first_print(&text('create_remote', $config{'remote'}));
	local $rv = &remote_oracle_call("create_oracle_database", $d, $dbname);
	if ($rv) {
		# Add to DB list in local domain object
		&second_print($virtual_server::text{'setup_done'});
		local @dbs = split(/\s+/, $d->{'db_'.$module_name});
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
local $init_new = &init_ora_dir()."/init$dbname.ora";
local $ex = &execute_command(&command_as_user($config{'unix'}, 0,
	"cp ".quotemeta($init_template)." ".quotemeta($init_new)),
	undef, \$out, \$out);
if ($ex) {
	&second_print(&text('create_failed', "<tt>$out</tt>"));
	return 0;
	}

# Edit file to use correct new parameters
local $lref = &read_file_lines($init_new);
local %done;
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
local ($ok, $out) = &execute_oracle_sql($dbname, "startup nomount");
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
local ($ok, $out) = &execute_oracle_sql($dbname,
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
	local ($ok, $out) = &execute_oracle_sql($dbname, "create rollback segment ${dbname}rbs storage ($config{'rollbacksize'} autoextend on next 10M maxsize unlimited);");
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
	local ($ok, $out) = &execute_oracle_sql($dbname, "\@?/rdbms/admin/catalog.sql");
	&second_print($virtual_server::text{'setup_done'});
	}

# Create procedures
if ($config{'catproc'}) {
	&first_print($text{'create_catproc'});
	local ($ok, $out) = &execute_oracle_sql($dbname, "\@?/rdbms/admin/catproc.sql");
	&second_print($virtual_server::text{'setup_done'});
	}

# Create product user profile
if ($config{'pupbld'}) {
	&first_print($text{'create_pupbld'});
	local ($ok, $out) = &execute_oracle_sql($dbname, "\@?/sqlplus/admin/pupbld.sql");
	&second_print($virtual_server::text{'setup_done'});
	}

# Create and grant users
foreach my $u ([ $d->{'user'}, $d->{'pass'} ],
	       [ $config{'user'}, $config{'pass'} ]) {
	&first_print(&text('create_user', $u->[0]));
	local ($ok, $out) = &execute_oracle_sql($dbname, "create user $u->[0] identified by \"$u->[1]\";");
	if (!$ok) {
		&second_print(&text('create_failed', "<pre>$out</pre>"));
		return 0;
		}
	local ($ok, $out) = &execute_oracle_sql($dbname, "grant all privileges to $u->[0];");
	if (!$ok) {
		&second_print(&text('create_failed', "<pre>$out</pre>"));
		return 0;
		}
	&second_print($virtual_server::text{'setup_done'});
	}

# Add to tnsnames.ora
&first_print($text{'create_tnsnames'});
local $lref = &read_file_lines($tnsnames_file);
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
local @dbs = split(/\s+/, $d->{'db_'.$module_name});
push(@dbs, $dbname);
$d->{'db_'.$module_name} = join(" ", @dbs);

return 1;
}

# delete_oracle_database(&domain, dbname)
# Delete all files used by some oracle DB
sub delete_oracle_database
{
local ($d, $dbname) = @_;

if ($config{'remote'}) {
	# Call on remote
	&first_print(&text('delete_remote', $config{'remote'}));
	local $rv = &remote_oracle_call("delete_oracle_database", $d, $dbname);
	if ($rv) {
		# Delete from DB list in local domain object
		&second_print($virtual_server::text{'setup_done'});
		local @dbs = split(/\s+/, $d->{'db_'.$module_name});
		@dbs = grep { $_ ne $dbname } @dbs;
		$d->{'db_'.$module_name} = join(" ", @dbs);
		}
	else {
		&second_print($text{'create_remoteerr'});
		}
	return $rv;
	}

# Shut down the DB
local @files = &oracle_database_files($dbname);
&first_print(&text('delete_shutdown', $dbname));
local ($ok, $out) = &execute_oracle_sql($dbname, "shutdown immediate;");
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
local $init_new = &init_ora_dir()."/init$dbname.ora";
unlink($init_new);
&second_print($virtual_server::text{'setup_done'});

# Delete from tnsnames.ora
&first_print($text{'delete_tnsnames'});
local $lref = &read_file_lines($tnsnames_file);
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
local @dbs = split(/\s+/, $d->{'db_'.$module_name});
@dbs = grep { $_ ne $dbname } @dbs;
$d->{'db_'.$module_name} = join(" ", @dbs);

return 1;
}

# modify_oracle_database(&domain, dbname)
# Sets a user's password in a database
sub modify_oracle_database
{
local ($d, $dbname) = @_;
&first_print(&text('modify_pass', $dbname));
local ($ok, $out) = &execute_oracle_sql($dbname, "alter user $d->{'user'} identified by \"$d->{'pass'}\";");
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
local ($dbname) = @_;
if ($config{'remote'}) {
	return &remote_oracle_call("oracle_database_files", $dbname);
	}

local @rv;
foreach my $cmd ('select name from V$DATAFILE;',
		 'select member from V$LOGFILE;',
		 'select value from v$parameter where name like \'log_archive_dest%\'',
		 'select name from v$controlfile;',
		 'select value from v$parameter where name like \'%dest\';',
		 ) {
	local ($ok, $out) = &execute_oracle_sql($dbname, $cmd);
	foreach my $l (split(/\r?\n/, $out)) {
		if ($l =~ /^\// && -r $l) {
			local @st = stat($l);
			push(@rv, [ $l, $st[7] ]);
			}
		}
	}
return @rv;
}

# list_tables(dbase)
sub list_tables
{
local ($db) = @_;
local $d = &execute_sql($db, "select table_name from user_tables");
return map { $_->[0] } @{$d->{'data'}};
}

sub can_edit_db
{
local ($db) = @_;
return 1 if ($access{'db'} eq '*');
local @dbs = split(/\t+/, $access{'db'});
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
local $i;
for($i=0; $i<$_[0]; $i++) {
	print "<tr $cb>\n";
	print "<td><input name=field_$i size=20></td>\n";
	print "<td><select name=type_$i>\n";
	print "<option selected>\n";
	local $t;
	foreach $t (@type_list) {
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
local @fields = @{$_[0]};
local $i;
local (@auto, @pri);
for($i=0; defined($in{"field_$i"}); $i++) {
	next if (!$in{"field_$i"});
	$in{"field_$i"} =~ /^\S+$/ ||
		&error(&text('table_efield', $in{"field_$i"}));
	$in{"type_$i"} || &error(&text('table_etype', $in{"field_$i"}));
	if ($in{"type_$i"} eq 'char' || $in{"type_$i"} eq 'varchar' ||
	    $in{"type_$i"} eq 'varchar2') {
		$in{"size_$i"} || &error(&text('table_esize', $in{"field_$i"}));
		}
	if ($in{"type_$i"} eq 'enum' || $in{"type_$i"} eq 'set') {
		local @ev = split(/\s+/, $in{"size_$i"});
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
local @sql;
local $sql = "create table ".&quotestr($_[1])." (".join(",", @fields).")";
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
local ($db, $table) = @_;
if ($config{'remote'}) {
	# Pass through to remote
	return &remote_oracle_call("table_structure", $db, $table);
	}

local $d = &execute_sql($db, "select * from $table where 0 = 1");
local $dbh = &get_dbi_handle($db);

# Get the table info
local $tbl = $dbh->table_info(undef, undef, $table, 'TABLE');
my $t = $tbl->fetchrow_hashref();
my $schema = $t->{'TABLE_SCHEM'};
$tbl->finish();

# Get primary keys
local $pri = $dbh->primary_key_info(undef, $schema, $table);
local %ispri;
while(my $p = $pri->fetchrow_hashref()) {
	$ispri{$p->{'COLUMN_NAME'}} = 'PRI';
	}
$pri->finish();

# Get the table structure
local @rv;
foreach my $c (@{$d->{'titles'}}) {
	local $info = $dbh->column_info(undef, undef, $table, $c);
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
local ($func, @args) = @_;
if (!$done_remote_require) {
	# Do the require first
	&remote_foreign_require($config{'remote'}, $module_name,
				"virtualmin-oracle-lib.pl");
	local %rconfig = %config;
	delete($rconfig{'remote'});
	$rconfig{'remoted'} = 1;
	local $ser = &serialise_variable(\%rconfig);
	&remote_eval($config{'remote'}, "virtualmin_oracle",
	     "\$c = &unserialise_variable(\"$ser\"); \%config = \%\$c;");
	}
return &remote_foreign_call($config{'remote'}, $module_name, $func, @args);
}

# oracle_database_exists(name)
# Checks if some Oracle DB exists or not
sub oracle_database_exists
{
local ($dbname) = @_;
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
	local $dir = &init_ora_dir();
	local @rv;
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
local %defs;
&read_env_file($default_dbs_file, \%defs);
return $defs{$remote_user};
}

sub set_default_db
{
local %defs;
&read_env_file($default_dbs_file, \%defs);
$defs{$remote_user} = $_[0];
&write_env_file($default_dbs_file, \%defs);
}

1;

