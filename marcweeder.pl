#!/usr/local/bin/perl

# marcweeder.pl

use strict;
use Getopt::Long;
use bytes;        # operate on bytes instead of characters
use autodie;      # default backup if nothing explicity implemented
use FileHandle;   # allows for a nicer progress indicator
use Cwd;

use constant TAG => 0;
use constant VAL => 1;

use constant ESCAPE             => "\x1b";
use constant RECORD_TERMINATOR  => "\x1d";
use constant FIELD_TERMINATOR   => "\x1e";

# even with autodie, using $fopen gives friendlier error for the general user
my ($inifile, $config, $count, $infile, $outfile, $pctrec);
my ($fopen, $marcrec, $recnum, $ismatch, $chkme, $thisfield);
my ($numthisfields, $indicatorsok, $specmatches, $checkleaderonly);
my ($inputrecs, $recctr, $onepct, $matchctr, $extracton, $progpct);
my ($rec_leader, $rec_directory, $rec_fields, $testing, $testdiag);

$matchctr = $recctr = $count = $inputrecs = 0;
$extracton = $config = $progpct = $checkleaderonly = 0;

my @chkfields;   # fields to check for a record

# for storing config data...
my (@chkinvertall, @chkldrpos, @chkf, @chkind1, @chkind2, @chkfwhich, @chkfhas);
my (@chkfcase, @chkfdata, @chksubf, @chksubfwhich, @chksubfhow);
my (@chksubfmatch, @chksubfcase, @chksubfdata);

my %cfgerror = (
  'LDRLENBAD'  => "Bad LDR length specified; must be: '>' or '<', then 2 - 5 digits\n",
  'LDRLBLBAD'  => "Bad LDR position label specified: must be 2 digit\n          acceptable leader position\n",
  'LDRCHRBAD'  => "Bad LDR position value specified: must legal single character\n",
  'BADFIELD'   => "Bad field specification\n",
  'BADWHICH'   => "Bad -which- specification\n",
  'BADIND'     => "Bad indicator specification\n",
  'SPECNOTEXP' => "Unexpected configuration specification\n",
  'SUBFMATCH'  => "Bad subfield -match- specification\n",
  'SPECNUMERR' => "Incorrect number of spec fields...\n",
  'CTLNOSUBF'  => "Cannot have a subfield specification for a control field\n",
);

# "prototype" declarations for clean compile
sub usage;
sub parse_record;

# acquire and handle parameters
if ((@ARGV < 1) or (! GetOptions('config' => \$config,
                                 'infile=s' => \$infile,
                                 'outfile=s' => \$outfile,
                                 'count' => \$count,
                                 'inifile=s' => \$inifile,
                                 'progpct' => \$progpct,
                                 'testing' => \$testing,
                                 'testdiag' => \$testdiag)))

  {usage();}                 

# built-in self testing
# creates some MARC data, runs tests and compares to expected results
my $currdir = getcwd;
if ($testing) {testme();}

# use default .ini file if no other supplied
if ($inifile eq '') {$inifile = "marcweeder.ini";}

if ($config)
{
  selfconfig();  # get parms and create .ini file
  exit(0);
}

if (!$count and !$testdiag)
{
  $extracton = 1;
  if ($outfile eq '') {usage();}
}

if (! -e $inifile) {die "ini file <$inifile> not found\n";}
if (! -s $inifile) {die "ini file <$inifile> is empty\n";}

getconfig();

$/ = RECORD_TERMINATOR;   # for MARC
autoflush STDOUT 1;       # useful for progress indicator

if ($extracton)
{
  $fopen = sprintf("Cannot open file %s for output\n", $outfile);
  open(OUTFILE, ">", $outfile) or die $fopen;
}

$fopen = sprintf("Cannot open file %s for input\n", $infile);
open(INFILE, "<", $infile) or die $fopen;

if ($progpct)   # will show real time percent processed
{
  # need record count in advance
  while ($pctrec = <INFILE>) {$inputrecs++;}
  $onepct = int(($inputrecs / 100) + 0.5);

  close(INFILE);
  open(INFILE, "<", $infile) or die $fopen;
}

# parse record
while ($marcrec = <INFILE>)
{
  $recctr++;

  # show progress as percentage or total so far  
  if ($progpct)
  {
    if (($recctr % $onepct) == 0)
      {printf("%s\% records checked\r", $recctr / $onepct);}
  }
  else
  {
    if (($recctr > 9999) and (($recctr % 1000) == 0))
      {print "Records checked: $recctr\r";}
  }

  $specmatches = 0;
  undef $recnum;

  # parse record
  ($rec_leader, $rec_directory, $rec_fields) = parse_record(\$marcrec);

  # apply each condition check to the current record
  for ($chkme=0; $chkme<@chkf; $chkme++)
  {
    $ismatch = checkarec();   # does this record match the search spec?
    if ($chkinvertall[$chkme]) {$ismatch = !$ismatch;}
    if ($ismatch) {$specmatches++;}
  }
  if ($specmatches == scalar(@chkf))   # must match all supplied specs
  {
    $matchctr++;
    if ($extracton) {print OUTFILE $marcrec;}
  }
}
close(INFILE);
if ($extracton) {close(OUTFILE);}

if ($testdiag) {testme_output();}

print "\r" . ' 'x30 . "\n";   # remove progress indicator
printf("%s record%s read\n", $recctr, ($recctr == 1 ? '' : 's') );
printf("%s match%s found\n", $matchctr, ($matchctr == 1 ? '' : 'es') );


sub checkarec
# apply the search spec to see if the current record is a match
{
  my $ismatch;

  if ($checkleaderonly)
  {
    # will have only that ONE spec, so we're done after checking that
    if (!(leaderisok($rec_leader, \%{$chkf[$chkme]})))
         {$ismatch = 0;}
    else {$ismatch = 1;}
    return $ismatch;
  }

  # normal field/subfield checking, with/without leader
  if (%{$chkldrpos[$chkme]} != ())   # if need to check leader
  {
    # if leader check fails, stop checking this record
    if (!(leaderisok($rec_leader, \%{$chkldrpos[$chkme]}))) {return 0;}
  }

  $ismatch = $indicatorsok = 0;

  # check only specified field's occurrences
  @chkfields = grep {$_->[TAG] eq $chkf[$chkme]} @$rec_fields;
  $numthisfields = scalar(@chkfields);
  last if ($numthisfields == 0);   # skip this record if no relevant fields found

  foreach $thisfield (@chkfields)   # remove field terminator at field end
  {
    if ($thisfield->[VAL] =~ /\x1e$/) {chop $thisfield->[VAL];}
  }

  if ($chkfwhich[$chkme] =~ /any|all/)       # actually check all THIS fields, but...
  {
    if ($chksubf[$chkme] eq ESCAPE)     # field check
    {
      foreach $thisfield (@chkfields)
      {
        $indicatorsok = indcheck($thisfield, $chkind1[$chkme], $chkind2[$chkme]);
        if ($indicatorsok)
        {
          # counting all matches in case it's an <all> check
          $ismatch += datacompare($thisfield->[VAL], $chkfdata[$chkme],
                                  $chkfcase[$chkme], $chkfhas[$chkme]);
        }
      }
      if ($chkfwhich[$chkme] eq 'all')       # ...if check all, must truly match all
      {
        if ($ismatch != scalar(@chkfields)) {$ismatch = 0;}
      }
      if ($ismatch > 0) {$ismatch = 1;}   # restore booleaness
    }
    else   # subfield check
    {
      foreach $thisfield (@chkfields)
      {
        $ismatch = subfdatacheck($thisfield, $chkind1[$chkme], $chkind2[$chkme],
                                 $chksubf[$chkme],     $chksubfwhich[$chkme],
                                 $chksubfhow[$chkme],  $chksubfmatch[$chkme],
                                 $chksubfcase[$chkme], $chksubfdata[$chkme]);
        # with "any", first match means we're done here
        if (($ismatch) and ($chkfwhich[$chkme] =~ /any/)) {return 1;}
      }
    }
  }
  else   # first or last check...
  {
    if ($chkfwhich[$chkme] eq 'first')
      {$thisfield = $chkfields[0];}
    else
      {$thisfield = $chkfields[$numthisfields-1];}   # last

    if ($chksubf[$chkme] eq ESCAPE)
    {
      $indicatorsok = indcheck($thisfield, $chkind1[$chkme], $chkind2[$chkme]);
      if ($indicatorsok)
      {
        $ismatch = datacompare($thisfield->[VAL], $chkfdata[$chkme],
                               $chkfcase[$chkme], $chkfhas[$chkme]);
      }
    }
    else   # subfield check
    {
      $ismatch = subfdatacheck($thisfield, $chkind1[$chkme], $chkind2[$chkme],
                               $chksubf[$chkme],     $chksubfwhich[$chkme],
                               $chksubfhow[$chkme],  $chksubfmatch[$chkme],
                               $chksubfcase[$chkme], $chksubfdata[$chkme]);
    }
  }
  return $ismatch;
}

sub leaderisok
# invoked if spec calls for leader check.
# record length part is optional.
# positions are always checked, but only those specified
{
  my ($recleader, $leaderpos_hashref) = @_;

  my %leaderpos = %$leaderpos_hashref;
  my ($ldrcondition, $checkhow, $length, $pos);
  
  # check specified positions
  foreach $pos (sort keys %leaderpos)
  {
    if ($pos eq 'rlen')   # record length check, if specified
    {
      ($checkhow, $length) = ($leaderpos{$pos} =~ /(.)(.+)/);
      if ($checkhow eq '>')
      {
        if (!(int(substr($recleader, 0, 5)) > $length)) {return 0;}
      }
      if ($checkhow eq "<")
      {
        if (!(int(substr($recleader, 0, 5)) < $length)) {return 0;}
      }
    }
    else   # position check; done always if have leader spec
    {
      $leaderpos{$pos} =~ s/\#/ /;
      if ($leaderpos{$pos} ne substr($recleader, int($pos), 1)) {return 0;}
    }
  }
  # made it this far, so we're good
  return 1;
}


sub indcheck
{
  my ($thisfield, @chk) = @_;

  # no indicators for the control fields
  if ($thisfield->[TAG] lt '010') {return 1;}
  
  my $i;
  my @inds;
  my @not = (0, 0);
  my @ismatch = (1, 1);

  for $i (0,1)   # get <not> info if present
  {    
    if ($chk[$i] =~ /~./)
    {
      $not[$i] = 1;
      $chk[$i] = chop($chk[$i]);   # retain indicator character only
    }
  }

  (@inds) = ($thisfield->[VAL] =~ /(.)(.).*/);   # "grab" the indicators to check
  for $i (0,1)   # actual check
  {
    if ($chk[$i] ne '*')
    {
      if ($chk[$i] ne $inds[$i]) {$ismatch[$i] = 0;}   # both must match
      if ($not[$i]) {$ismatch[$i]  = !$ismatch[$i];}
    }
  }

  if ($ismatch[0] and $ismatch[1]) {return 1;}
  else                             {return 0;}
}


sub subfdatacheck
{
  my ($thisfield, $ind1, $ind2, $subf, $which, $how, $match, $case, $data) = @_;

  my ($lastsubf, $thissubfctr, $idx, $localidx, $ismatch, $indicatorsok);
  my (@subfields, @subfldid, @subfdata);

  $thissubfctr = $localidx = $ismatch = 0;

  # stop if fail indicator check
  $indicatorsok = indcheck($thisfield, $ind1, $ind2);
  if (!$indicatorsok) {return 0;}
  
  @subfields = split /\x1f/, $thisfield->[VAL];

  # start looking at 1, since zeroth part is the indicators
  # get arrays of subfield IDs and subfields' data
  for ($idx=1; $idx<@subfields; $idx++)
  {
    $subfields[$idx] =~ /(.)(.*)/;
    if ($1 eq $subf)   # keep only the subfields we want to check
    {
      $subfldid[$localidx] = $1;
      $subfdata[$localidx] = $2;
      $localidx++;
    }
  }
  if (scalar(@subfldid) == 0) {return 0;}   # nothing to check

  $lastsubf = -1;
  for ($idx=0; $idx<@subfdata; $idx++)
  {
    $thissubfctr++;
    if    ($which =~ /any|all/)
    {
      # count matches in case it's an <all> check
      $ismatch += datacompare($subfdata[$idx], $data, $case, $match, $how);
        
      # if have at least one match on ANY check, we're done
      if (($which =~ /any/) and ($ismatch)) {return 1;}
    }
    elsif (($which eq 'first') and ($idx == 0))
    {
      $ismatch = datacompare($subfdata[$idx], $data, $case, $match, $how);
    }
    elsif ($which eq 'last') {$lastsubf = $idx;}
  }
  if ($lastsubf ne -1)   # must check <last> THIS subfield
  {
    $ismatch = datacompare($subfdata[$lastsubf], $data, $case, $match, $how);
  }
  if ($which eq 'all')   # must have matched <all> THIS subfield
  {
    if ($ismatch != $thissubfctr) {$ismatch = 0;}
  }
  if ($ismatch > 0) {$ismatch = 1;}   # restore booleaness

  return $ismatch;
}


sub datacompare
# used for both fields and subfields; input is conditions and raw data
{
  my ($data, $matchvalue, $caseexact, $mustmatch, $how) = @_;

  my $rx;
  my $ismatch = 0;
  my $case = '';

  # hash of matches for the current match value and conditions; simplifies code below
  my %rxp = (
       sd  => qr/^$matchvalue/,    # startswith, case sensitive
       sdi => qr/^$matchvalue/i,   # startswith
       cd  => qr/$matchvalue/,     # contains, case sensitive
       cdi => qr/$matchvalue/i,    # contains
       ed  => qr/$matchvalue$/,    # endswith, case sensitive
       edi => qr/$matchvalue$/i,   # endswith
  );

  if (!$caseexact) {$case = 'i';}

  if (scalar(@_) == 4)   # field comparison
    {$rx = "cd$case";}
  else                   # subfield comparison has extra argument to this subroutine
    {$rx = substr($how, 0, 1) . 'd' . $case;}

  if ($data =~ /$rxp{$rx}/) {$ismatch = 1;}   # the actual match check

  if (!$mustmatch) {return !$ismatch;}
  else             {return  $ismatch;}
}


sub parse_record()
{
  my ($strref) = @_;
  
  my ($reclen, $baseaddr, $leader, $directory, $tagid, $taglen, $offset, $tagdata);
  my @fields;

  if ($$strref !~ /
      \A
              # bytes description
              # ----- -------------------------------------------
      (\d{5}) # 00-04 rec length
      (....)  # 05-08 rec status, rec type, rec level, type of control
      (.)     # 09    character coding
      (..)    # 10-11 indicator count, subfield code count
      (\d{5}) # 12-16 base address = length of leader + directory
      (.{7})  # 17-23 other stuff
    /x)
  {
    error("Not a USMARC record: bad leader");
    exit -1;
  }

  ($reclen, $baseaddr) = ($1, $5);
  if ($reclen != length($$strref))
  {
    warning("Record length mismatch");   # maybe want error instead?
  }

  $leader    = substr($$strref, 0, 24);
  $directory = substr($$strref, 24, $baseaddr-24);
  if (length($directory) % 12 != 1)
  {
    # ERR Dir length (less trailing field terminator)...
    error("Directory length not a multiple of 12 bytes");
  }
  if (substr($directory, -1, 1) ne FIELD_TERMINATOR)
  {
    error("Directory not terminated");
  }

  # get the fields' data
  while ($directory =~ /(...)(....)(.....)/gc)
  {
    ($tagid, $taglen, $offset) = ($1, $2, $3);
    if ($taglen =~ /\D/ || $offset =~ /\D/)
    {
      error("Directory contains non-numeric field length or offset");
    }
    $tagdata = substr($$strref, $baseaddr+$offset, $taglen);
    if ($tagid eq '001') {$recnum = $tagdata;}   # for error, warning output
    if (substr($tagdata, -1, 1) ne FIELD_TERMINATOR)
    {
      error("Unterminated field '$tagid'");
    }
    push @fields, [$tagid, $tagdata];
  }
  return ($leader, $directory, \@fields);
}


sub getconfig
# read parameters from ini file so know what to do
# when determining field or subfield spec via number of pieces in the spec,
# the apparent ambivalence is due the optional presence of the leader part
{
  my ($ldr, $part, $pos, $value, $invertall, $field, $ind1, $ind2, $fieldwhich);
  my ($fieldhas, $fielddata, $fieldcase, $matchmod, $subfield, $subfwhich, $subfmatch);
  my ($subfhow, $subfdata, $subfcase, $idx);

  $idx = -1;
  $ldr = '';

  my (@inilines, @specs, @ldrparts);

  my %ldrhash;
  my %whichhash = (first => 1, any => 1, all => 1, last => 1);
  my %withinhash = (startswith => 1, contains => 1, endswith => 1);
  my %goodldrpos = ('05' => '1', '06' => '1', '07' => '1', '08' => '1', '09' => '1',
                    '17' => '1', '18' => '1', '19' => '1');


# anonymous subroutine declarations for better variable scope
  my $_nextline = sub
  {
    my ($mode) = @_;

    $idx++;
    # ignore blank lines and comments
    while (($idx <= @inilines) and
           ((length($inilines[$idx]) == 0) or ($inilines[$idx] =~ /\A#/)))
      {$idx++;}
    last if ($idx > @inilines);
  };

  my $_getleaderstuff = sub
  {
    if ($ldr ne '')
    {
      @ldrparts = split /\./, $ldr;
      foreach $part (@ldrparts)
      {
        ($pos, $value) = split /:/, $part;

        if ($pos eq 'rlen')
        {
          if ($value !~ /^[<|>]\d{2,5}$/)
            {die_in_config('LDRLENBAD', $inilines[$idx]);}
        }
        elsif (!exists($goodldrpos{"$pos"}))
          {die_in_config('LDRLBLBAD', $inilines[$idx]);}
        elsif ($value !~ /^[abcdefghijklmnopqrstuvwxyz0123456789# ]{1}$/)
          {die_in_config('LDRCHRBAD', $inilines[$idx]);}
        $ldrhash{$pos} = $value;
      }
    }
    else {%ldrhash = ();}
  };
  
  my $_handlefieldpart = sub
  {
    if ($field !~ /^\d\d\d$/) {die_in_config('BADFIELD', $inilines[$idx]);}

    # if an indicator is a not-match (~x), that logic is handled later
    if ($ind1 eq '') {$ind1 = '*';}
    if ($ind2 eq '') {$ind2 = '*';}
    if ((length($ind1) > 2) or (length($ind2) > 2) or
        ($ind1 eq '~*') or ($ind2 eq '~*') or
        ($ind1 eq '~')  or ($ind2 eq '~')) {die_in_config('BADIND', $inilines[$idx]);}

    $fieldwhich = lc($fieldwhich);
    if (!exists($whichhash{$fieldwhich})) {die_in_config('BADWHICH', $inilines[$idx]);}
  };

  # get the config data
  if (! -e $inifile) {die ".ini file <$inifile> not found\n";}
  my $fopen = sprintf("Cannot open file %s for input\n", $inifile);
  open(INIFILE, "<", $inifile) or die $fopen;
  @inilines = <INIFILE>;
  close(INIFILE);
  chomp @inilines;

  # internalize the config data
  while ($idx <= @inilines)
  {
    $invertall = $fieldcase = $subfcase = 0;
    $fieldhas = $subfmatch = 1;
    $ldr = $fielddata = $fieldwhich = $subfield = $subfwhich = '';
    $subfhow = $subfwhich = $matchmod = '';

    $_nextline->();
    # detect if need to negate entire search and remove that indicator if present
    if ($inilines[$idx] =~ /^\~/)
    {
      $invertall = 1;
      $inilines[$idx] =~ s/^\~//;
    }

    @specs = split /\|/, $inilines[$idx];

    if (scalar(@specs) == 1)                                 # leader only
    {
      $ldr = $inilines[$idx];
      $_getleaderstuff->();
      # using that array since that one is checked for number of specs
      # we have (and is otherwise always populated)
      push @chkf, \%ldrhash;
      $checkleaderonly = 1;
      # since leader only, we're done here
      return;
    }
    elsif ((scalar(@specs) == 6) or (scalar(@specs) == 7))   # field spec
    {
      if (scalar(@specs) == 6)
      {
        ($field, $ind1, $ind2, $fieldwhich,
         $matchmod, $fielddata) = split /\|/, $inilines[$idx];
      }
      else
      {
        ($ldr, $field, $ind1, $ind2, $fieldwhich,
         $matchmod, $fielddata) = split /\|/, $inilines[$idx];
        $_getleaderstuff->();
      }
      $_handlefieldpart->();

      # valid characters: [c~], either or both
      if (length($matchmod) > 2) {die_in_config('SPECNOTEXP', $inilines[$idx]);}
      if ($matchmod ne '')
      {
        if ($matchmod =~ /c/i) {$fieldcase = 1;}
        if ($matchmod =~ /\~/) {$fieldhas = 0;}   # not match
      }
    }
    elsif ((scalar(@specs) == 9) or (scalar(@specs) == 10))   # subfield spec
    {
      if (scalar(@specs) == 9)
      {
        ($field, $ind1, $ind2, $fieldwhich,
         $subfield, $subfwhich, $subfhow,
         $matchmod, $subfdata) = split /\|/, $inilines[$idx];
      }
      else
      {
        ($ldr, $field, $ind1, $ind2, $fieldwhich,
         $subfield, $subfwhich, $subfhow,
         $matchmod, $subfdata) = split /\|/, $inilines[$idx];
        $_getleaderstuff->();
      }
      $_handlefieldpart->();

      if ($field lt '010') {die_in_config('CTLNOSUBF', $inilines[$idx]);}
      
      $subfwhich = lc($subfwhich);
      if (!exists($whichhash{$subfwhich})) {die_in_config('BADWHICH', $inilines[$idx]);}

      $subfhow = lc($subfhow);
      if (!exists($withinhash{$subfhow})) {die_in_config('SUBFMATCH', $inilines[$idx]);}

      if (length($matchmod) > 2) {die_in_config('SPECNOTEXP', $inilines[$idx]);}
      # valid characters: [c~], either or both
      if ($matchmod ne '')
      {
        if ($matchmod =~ /c/i) {$subfcase = 1;}
        if ($matchmod =~ /\~/) {$subfmatch = 0;}   # not match
      }
    }
    else {die_in_config('SPECNUMERR', $inilines[$idx]);}   # general failure

    # store the config parameters
    if ($fielddata ne '')
    {
      push @chkldrpos, \%ldrhash;
      push @chkf, $field;
      push @chkind1, $ind1;
      push @chkind2, $ind2;
      push @chkfwhich, $fieldwhich;
      push @chkfdata, $fielddata;
      push @chkfhas, $fieldhas;
      push @chkfcase, $fieldcase;
      push @chksubf, ESCAPE;
      push @chksubfwhich, ESCAPE;
      push @chksubfhow, ESCAPE;
      push @chksubfmatch, ESCAPE;
      push @chksubfcase, ESCAPE;
      push @chksubfdata, ESCAPE;
      push @chkinvertall, $invertall;
    }
    else   # subfield data
    {
      push @chkldrpos, \%ldrhash;
      push @chkf, $field;
      push @chkind1, $ind1;
      push @chkind2, $ind2;
      push @chkfwhich, $fieldwhich;
      push @chkfdata, ESCAPE;
      push @chkfhas, ESCAPE;
      push @chkfcase, ESCAPE;
      push @chksubf, $subfield;
      push @chksubfwhich, $subfwhich;
      push @chksubfhow, $subfhow;
      push @chksubfmatch, $subfmatch;
      push @chksubfcase, $subfcase;
      push @chksubfdata, $subfdata;
      push @chkinvertall, $invertall;
    }

    $invertall = $fieldhas = $subfmatch = 0;
    $fieldwhich = $subfield = $subfwhich = $subfhow = $subfdata = '';
  }   # end of for inilines
}


sub warning
{
  my ($msg) = @_;

  printf STDERR "Warning: [%s] at record %d (Rec ID %s) of file %s\n",
      $msg, $recctr, (defined $recnum ? $recnum : 'unknown'), $infile;
}


sub error
{
  my ($msg) = @_;
  printf STDERR "Error: [%s] at record %d (Rec ID %s) of file %s\n",
      $msg, $recctr, (defined $recnum ? $recnum : 'unknown'), $infile;
  exit(1);
}


sub die_in_config
{
  my ($errcode, $configline) = @_;

  print "\n   CONFIGURATION ERROR in file [$inifile]\n\n";
  print "     at line [$configline]\n\n";
  print "   ERROR: $cfgerror{$errcode}\n\n";
  exit(1);
}


sub selfconfig
{
  my ($prompt, $moreconfig, $answer, $reclen, $ldrlen, $ldrcondition);
  my ($pos, $ldrstring, $haveleader);
  
  my %leaderpos;

  $reclen = $haveleader = 0;
  $moreconfig = 'Y';
  $ldrstring = '';

  # blank out existing inifile, since config data
  # is written in append mode
  open(INIFILE, ">", $inifile);
  close(INIFILE);

  print "SELF-CONFIG mode\n\n";
  print "Configuration takes place one line at a time.\n";
  print "Data currently goes to the default marcweeder.ini file in\n";
  print "the current directory.\n\n";

  while ($moreconfig eq 'Y')
  {
    $ldrstring = '';
    if (!$haveleader)
    {
      $prompt = "\nDo you want a leader match? Y/N: ";
      $answer = getachar($prompt, 'YN', 'N');
      print "\n";
      if ($answer eq 'Y')
      {
        ($ldrlen, %leaderpos) = getleader();
        $haveleader = 1;
        # prep data for .ini output
        ($ldrcondition, $reclen) = split /:/, $ldrlen;

        # serialize ldr data for .ini writing
        if ($reclen != 0) {$ldrstring .= sprintf("rlen:$ldrcondition$reclen");}
        foreach $pos (sort keys %leaderpos)
        {
          if ($leaderpos{$pos} eq ' ') {$leaderpos{$pos} = "#";}
          # skipping blank (unspecified) positions
          if ($leaderpos{$pos} ne '') {$ldrstring .= sprintf(".$pos:$leaderpos{$pos}");}
        }
        $ldrstring =~ s/^\.//;   # remove leading ldr separator char if no len spec
        print "\n\n";

        $prompt =  "Also look for field or subfield match? Y/N: ";
        # quietly allow (F)ield or (S)ubfield selection here, also
        $answer = getachar($prompt, 'YNFS', 'N');

        if ($answer eq 'N')
        {
          # since looking for leader match only, write config data and exit
          open(INIFILE, ">>", $inifile);
          if ($ldrstring ne '') {print INIFILE "$ldrstring";}
          close(INIFILE);
          exit(0);
        }

        print "\n";
        if ($answer ne 'N') {getfieldandorsubfield($ldrstring, $answer);}
      }
      else {getfieldandorsubfield($ldrstring, '');}
    }
    else {getfieldandorsubfield($ldrstring, '');}

    $prompt = "\nEnter another condition? Y/N: ";
    $moreconfig = getachar($prompt, 'YN', 'N');
    if ($moreconfig eq 'Y') {print "\n\n";}
  }
}


sub getleader
{
  my ($prompt, $continue, $reclen, $ldrcondition, $pos, $ldrlen);
  my %leaderpos = ('05' => '', '06' => '', '07' => '', '08' => '', '09' => '',
                   '17' => '', '18' => '', '19' => '');
  my $leaderchars = "abcdefghijklmnopqrstuvwxyz0123456789# ";

  $prompt = "Match on record length being more or less than some value? Y/N: ";
  $continue = getachar($prompt, 'YN', 'N');
  print "\n";
  if ($continue eq 'Y')
  {
    $prompt = "Enter a record length value: ";
    $reclen = getanumber($prompt, 5);
    print "\n";
    $prompt = "Select greater-than or less-than using characters '>' or '<' : ";
    $ldrcondition = getachar($prompt, '><');
  }
  print "\n";

  print "\nFor each leader position to be checked,\n";
  print "enter the value to look for.\n";
  print "To skip a position, just press <Enter>.\n\n";
  foreach $pos (sort keys %leaderpos)
  {
    $prompt = "Leader position $pos: ";
    $leaderpos{$pos} = getachar($prompt, $leaderchars);
  }

  if ($reclen != 0) {$ldrlen = "$ldrcondition:$reclen";}
  return($ldrlen, %leaderpos);
}


sub getfieldandorsubfield
{
  my ($ldrinistr, $whichget) = @_;

  my ($prompt, $mode, $field, $ind1, $ind2, $casematch, $whichf, $whichsubf);
  my ($data, $notdata, $invertall, $subf, $within, $csout, $oktoproceed);

  my %whichhash = (F => 'First', A => 'Any', E => 'Every', L => 'Last');
  my %withinhash = (S => 'Startswith', C => 'Contains', E => 'Endswith');

  $csout = '';
  $oktoproceed = 0;

  while (!$oktoproceed)
  {
    # (F)ield or (S)ubfield determination might be passed in
    if (($whichget eq 'F') or ($whichget eq 'S')) {$mode = $whichget;}
    else
    {
      print "Is this a field or subfield match specification?\n";
      $prompt = "Choose (F)ield-only or (S)ubfield-in-field: ";
      $mode = getachar($prompt, 'FS', 'N');
    }
    if ($mode eq 'F') {$oktoproceed = 1;}
    print "\n";

    $prompt = "Look at which field: ";
    $field = getfield($prompt);
    if ($mode eq 'S')
    {
      if ($field ge '010')
        {$oktoproceed = 1;}
      else
        {print "\n   Cannot enter a subfield condition for a control field ($field).\n\nContinuing...\n\n";}
    }
    print "\n";
  }

  if ($field ge '010')
  {
    print "Enter indicators. If it doesn't matter what a particular\n";
    print "indicator is, enter an asterisk '*' for that indicator.\n";
    print "If you wish to disallow a particular indicator character,\n";
    print "precede it with the tilde '~'.\n";
    $prompt = "Please enter first indicator value: ";
    $ind1 = getindicators($prompt);
    $prompt = "Please enter second indicator value: ";
    $ind2 = getindicators($prompt);
    print "\n";
    print "Some fields may occur multiple times in a record. You can specify\n";
    print "whether your match-data should occur only in the <first> or <last>\n";
    print "occurrence of a field, in <every> occurrence, or in <any> occurrence.\n";
    $prompt = "Choose (F)irst, (A)ny, (E)very, or (L)ast: ";
    $whichf = getachar($prompt, 'FAEL', 'N');
    print "\n";
  }
  else   # noop defaults for control fields
  {
    $ind1 = '*';
    $ind2 = '*';
    $whichf = 'F';
  }

  $prompt = "Is this a case sensitive data match? Y/N: ";
  $casematch = getachar($prompt, 'YN', 'N');
  if ($casematch eq 'Y') {$csout = ' case-sensitive';}
  print "\n";

  if ($mode eq 'F')
  {
    print "Enter field data to match: ";
    $data = <STDIN>;
    chomp $data;
    print "\n";

    print "So far we are looking for this match:\n\n";
    showleaderdata($ldrinistr);
    print "field:[$field] inds:<$ind1$ind2> match occurrence(s):[$whichhash{$whichf}]\n";
    print "                      has$csout data:[$data]\n\n\n";

    print "Now you can add some <not> or inverse conditions, if you like.\n";
    print "Do you want a match only if the specified data is NOT found?\n\n";
    print "Example:\n  ";
    showleaderdata($ldrinistr);
    print "  field:[$field] inds<$ind1$ind2> match occurrence(s):[$whichhash{$whichf}]\n";
    print "                 NOT (has$csout data [$data])\n\n";
    $prompt = "Not match on data; i.e., inverse data match? Y/N: ";
    $notdata = getachar($prompt, 'YN', 'N');
    print "\n";

    print "You can also invert the entire match specification if you like.\n\n";
    print "Example:\n";
    print "  NOT ( ";
    showleaderdata($ldrinistr);
    print "        field:[$field] inds<$ind1$ind2> match occurrence(s):[$whichhash{$whichf}]\n";
    if ($notdata eq 'Y')
      {print "                       NOT (has$csout data [$data])\n      )\n\n";}
    else 
      {print "                       has$csout data [$data]\n      )\n\n";}
    $prompt = "Invert the entire match? Y/N: ";
    $invertall = getachar($prompt, 'YN', 'N');

    # store field match config data
    open(INIFILE, ">>", $inifile);
    if ($invertall eq 'Y') {print INIFILE "~";}
    if ($ldrinistr ne '')  {print INIFILE "$ldrinistr|";}
                            print INIFILE "$field";
                            print INIFILE "|$ind1|$ind2|";
    $whichf = $whichhash{$whichf};
    if ($whichf eq 'Every') {$whichf = 'all'};
    $whichf = lc($whichf);
                            print INIFILE "$whichf|";
    if ($notdata eq 'Y')   {print INIFILE "~";}
    if ($casematch eq 'Y') {print INIFILE "c";}
                            print INIFILE "|$data\n";
    close(INIFILE);
  }
  else   # subfield mode
  {
    $prompt = "Look at which subfield: ";
    $subf = getsubfield($prompt);
    print "\n";

    print "Subfields may occur multiple times in a field. You can specify\n";
    print "whether your match-data should occur only in the <first> or <last>\n";
    print "occurrence of a subfield, in <every> occurrence, or in <any> occurrence.\n";
    $prompt = "Choose (F)irst, (A)ny, (E)very, or (L)ast: ";
    $whichsubf = getachar($prompt, 'FAEL', 'N');
    print "\n";

    print "You can choose where in the subfield you want to match the data.\n";
    $prompt = "Choose (S)tartswith, (C)ontains, or (E)ndwith: ";
    $within = getachar($prompt, 'SCE', 'N');
    print "\n";

    print "Enter subfield data to match: ";
    $data = <STDIN>;
    chomp $data;
    print "\n";

    print "So far we are looking for this match:\n\n";
    if ($casematch eq 'Y') {$csout = ' case-sensitive';}
    showleaderdata($ldrinistr);
    print "field:[$field] inds:<$ind1$ind2> match occurrence(s):[$whichhash{$whichf}]\n";
    print "  subfield:[$subf] match$csout occurrence(s):[$whichhash{$whichsubf}]\n";
    print "               match how:[$withinhash{$within}] for data [$data]\n\n\n";

    print "Now you can add some <not> or inverse conditions, if you like.\n";
    print "Do you want a match only if the specified data is NOT found?\n\n";
    print "Example:\n  ";
    showleaderdata($ldrinistr);
    print "  field:[$field] inds<$ind1$ind2> match occurrence(s):[$whichhash{$whichf}]\n";
    print "    subfield:[$subf] match$csout occurrence(s):[$whichhash{$whichsubf}]\n";
    print "                 NOT (match how:[$withinhash{$within}] for data [$data])\n\n";
    $prompt = "Not match on data; i.e., inverse data match? Y/N: ";
    $notdata = getachar($prompt, 'YN', 'N');
    print "\n";

    print "You can also invert the entire match specification if you like.\n\n";
    print "Example:\n";
    print "  NOT ( ";
    showleaderdata($ldrinistr);
    print "        field:[$field] inds<$ind1$ind2> match occurrence(s):[$whichhash{$whichf}]\n";
    print "          subfield:[$subf] match$csout occurrence(s):[$whichhash{$whichsubf}]\n";
    if ($notdata eq 'Y')
      {print "                       NOT (match how:[$withinhash{$within}] for data [$data])\n      )\n\n";}
    else 
      {print "                       match how:[$withinhash{$within}] for data [$data]\n      )\n\n";}
    $prompt = "Invert the entire match? Y/N: ";
    $invertall = getachar($prompt, 'YN', 'N');
    print "\n";

    # store subfield match config data
    open(INIFILE, ">>", $inifile);
    if ($invertall eq 'Y') {print INIFILE "~";}
    if ($ldrinistr ne '')  {print INIFILE "$ldrinistr|";}
                            print INIFILE "$field";
                            print INIFILE "|$ind1|$ind2|";
    $whichf = $whichhash{$whichf};
    if ($whichf eq 'Every') {$whichf = 'all'};
    $whichf = lc($whichf);
                            print INIFILE "$whichf|$subf|";
    $whichsubf = $whichhash{$whichsubf};
    if ($whichsubf eq 'Every') {$whichsubf = 'all'};
    $whichsubf = lc($whichsubf);
                            print INIFILE "$whichsubf|";
    $within = lc($withinhash{$within});
                            print INIFILE "$within|";
    if ($notdata eq 'Y')   {print INIFILE "~";}
    if ($casematch eq 'Y') {print INIFILE "c";}
                            print INIFILE "|$data\n";
    close(INIFILE);
  }
  print "INI file $inifile saved\n";
}


sub showleaderdata
# for feedback during selfconfig
{
  my ($ldrstring) = @_;

  my @pieces;
  my ($len, $pos, $value, $piece);

  @pieces = split /\./, $ldrstring;
  if ($pieces[0] =~ /^>|^</)   # have length value
    {(undef, $len) = split /:/, shift @pieces;}
  print "leader: ";
  if ($len ne '') {print "reclen$len ";}
  foreach $piece (@pieces)
  {
    ($pos, $value) = split /:/, $piece;
    if ($value eq ' ') {$value = '#';}   # LOC uses that char to indicate a space
    print "$pos=$value "
  }
  print "\n";
}


sub getachar
# prompt for specified single-char response. keeps displaying
# prompt and asking for input until acceptable input has
# been received. returns the acceptable char.
# used for sub selfconfig
{
  my ($prompt, $choices, $casesensitive) = @_;

  my ($char, $numchoices, $idx);
  my (@choice);

  if ($casesensitive eq 'N') {$choices = uc($choices);}
  @choice = split //, $choices;
  $numchoices = length($choices);

  while (1)
  {
    print $prompt;
    $char = <STDIN>;
    chomp $char;
    if ($casesensitive eq 'N') {$char = uc($char);}
    last if ($choices =~ /$char/);

    print "Acceptable response is: ";
    for ($idx=0; $idx<$numchoices-1; $idx++)
    {
      if ($choice[$idx] ne ' ') {print "$choice[$idx], ";}
      else                      {print "#, ";}
    }
    print "or ";
    if ($choice[$numchoices-1] ne ' ') {print "$choice[$numchoices-1]\n";}
    else                               {print "#\n";}
  }
  return $char;
}


sub getfield
# used for sub selfconfig
{
  my ($prompt) = @_;

  my $fld;

  while (1)
  {
    print $prompt;
    $fld = <STDIN>;
    chomp $fld;
    last if ($fld =~ /^\d\d\d$/);

    print "You must enter 3 digits to specify a field.\n"
  }
  return $fld;
}


sub getindicators
# used for sub selfconfig
{
  my ($prompt) = @_;

  my $ind;

  while (1)
  {
    print $prompt;
    $ind = <STDIN>;
    chomp $ind;
    if (($ind eq '~*') or ($ind eq '*~'))
    {
      print "Cannot have tilde with asterisk.\n";
      $ind = '';
    }
    last if ($ind =~ /(^\~[a-z0-9]$)|(^[a-z0-9]$)|(^\*$)/);

    print "Indicators can be lower case letter, digit, or \"wild card\" '*'.\n";
    print "Precede with the tilde '~' to disallow a character.\n";
  }
  return $ind;
}


sub getsubfield
# used for sub selfconfig
{
  my ($prompt) = @_;

  my $subf;

  while (1)
  {
    print $prompt;
    $subf = <STDIN>;
    chomp $subf;
    last if ($subf =~ /^([a-z0-9]){1}$/);

    print "A subfield can be a single lower case letter or digit\n";
  }
  return $subf;
}

sub getanumber
# used for sub selfconfig
{
  my ($prompt, $numdigits) = @_;

  my $number;

  while (1)
  {
    print $prompt;
    $number = <STDIN>;
    chomp $number;
    last if ($number =~ /^[0-9]{1,5}$/);

    print "Value must be all digits and no more than $numdigits digits\n";
  }
  return $number;
}


sub usage()
{
  print <<ENDUSAGE;

Usage: marcweeder   -config

       marcweeder   -infile=inputfilename

                    -outfile=outputfilename  |  -count

                  [ -inifile=inifilename ]

                  [ -progpct ]

   The -config option should be used by itself; it puts the program
   into self-config mode. You'll be prompted for the various parameters
   for a match condition and this data will be written to the default
   .ini file. (Overwrites existing file of same name.)

   For typical use, you must specify a MARC file to be checked, and
   either an output file or the count option. You will always get record
   counts of matching records, and matching records will be copied to
   outfile if supplied.

   The .ini file defaults to marcweeder.ini in the current directory.
   Optionally you can specify a .ini file with a name and location of
   your choosing.

   Another optional parameter is progpct. This provides a running
   percent-completed indication. This option may cause an initial delay
   if infile is very large and/or your system is not that fast.
   
   Anything other than the filenames you supply must be entered as
   shown above.
   
   For complete documentation, enter the command:
      perldoc [path-to]marcweeder.pl
ENDUSAGE
  exit(0);
}



sub testme_makemarcfile
# creates the MARC file(s) for testing
# converts from the ASCII-ized data found after the code
{
  my ($filename) = @_;

  my($tline, $thisrec);
  my $subfdelim = chr(0x1f);
  my $fdelim = chr(0x1e);
  my $recdelim = chr(0x1d);

  $tline = <DATA>; $tline = <DATA>;
  chomp $tline;
  while ($tline ne '')
  {
    $thisrec .= $tline;
    $tline = <DATA>;
    chomp $tline;
  }
  $thisrec =~ s!@@@@!$fdelim!g;
  $thisrec =~ s!@@@!$subfdelim!g;
  open(TESTMARC, ">", "$currdir/$filename");
  print TESTMARC "$thisrec$recdelim";
  close(TESTMARC);
}


sub testme_makeinifiles
# creates the .ini files for testing
{
  my (@filenamelist) = @_;

  my ($tline, $filename, $config, $test, $configs);

  $tline = <DATA>;
  while ($tline !~ /^end testini/)
  {
    ($filename, $config) = split /`/, $tline;
    open(INIFILE, ">", "$currdir/mwwww$filename");
    print INIFILE $config;
    close(INIFILE);
    ($test) = ($filename =~ /(\d+)/);
    chomp $config;
    # keep config info testing diagnostics for later
    $configs .= "$test`$config\@\@";
    push @filenamelist, "mwwww$filename";   # for deleting when done
    $tline = <DATA>;
  }
  chop $configs; chop $configs;
  # temporarily put config info on the filename array
  push @filenamelist, $configs;
  return @filenamelist;
}


sub testme_makeexpecthash
# creates a hash containing the expected results
{
  my ($tline, $testnum, $expect);
  my %expected = ();

  $tline = <DATA>;
  chomp $tline;
  while ($tline !~ /^end resultkey/)
  {
    ($testnum, $expect) = split /=/, $tline;
    $testnum = sprintf("%-2.2d", $testnum);
    $expected{$testnum} = $expect;
    $tline = <DATA>;
    chomp $tline;
  }
  return %expected;
}

sub testme_makescoreshash
# creates a hash containing the test results
{
  my ($tline, $testnum, $result);
  my %scores = ();
  my $testoutfile = 'mwwwwtest.txt';

  open(SCOREFILE, "<", "$currdir/$testoutfile");
  while ($tline = <SCOREFILE>)
  {
    chomp $tline;
    ($testnum, $result) = split /=/, $tline;
    $testnum = sprintf("%-2.2d", $testnum);
    $scores{$testnum} = $result;
  }
  close(SCOREFILE);
  return %scores;
}


sub testme_output
# used only with -testdiag parameter
# thus when an actual test is performed,
# append the result to a file
{
  my $testoutfile = 'mwwwwtest.txt';

  open(TFILE, ">>", "$currdir/$testoutfile");
  my ($num) = ($inifile =~ /(\d+)/);
  print TFILE "$num=$matchctr\n";
  close(TFILE);
  exit;
}


sub testme
# this subroutine is called when running marcweeder with the -testing parameter.
# all subroutines named testme[_something] are directly involved in the testing
# process.
# data for testing is located after the __END__ token.
# this data contains MARC data converted to ASCII, because this is a text file.
# this is followed by the config data to create some .ini files.
# last is the answer key.
#
# *this* subroutine controls the testing process. for each .ini file,
# marcweeder is called with the -testdiag parameter, which runs the
# specified test, and stores the (-count) results in a file.
# this file's data is compared to the expected results, and the findings
# displayed.

# all files generated for testing are created in the current directory and
# have names starting with "mwwww". these files are deleted when testing
# is done.
{
  my ($tline, $limit, $test, $result, $file, $configs, $cfg);
  my (@cfglines, @filenamelist);
  my (%confighash, %expected, %scores);

  my $testfile1 = 'mwwwwtest1.mrc';
  my $testfile2 = 'mwwwwtest2.mrc';
  my $testoutfile = 'mwwwwtest.txt';
  my $havefailure = 0;
  @cfglines = @filenamelist = ();
  
  # keep track of testing files created so can delete them when done
  push @filenamelist, $testfile1;
  push @filenamelist, $testfile2;

  # acquire test records and put in individual files
  $tline = <DATA>;
  while ($tline !~ /^BEGIN TEST SECTION/) {$tline = <DATA>;}
  testme_makemarcfile($testfile1);
  testme_makemarcfile($testfile2);

  # acquire .ini configurations and put in individual files
  while ($tline !~ /^begin testini/) {$tline = <DATA>;}
  @filenamelist = testme_makeinifiles(@filenamelist);

  # remove the config information from the filename array
  # and put in hash for test result comparison diagnostics
  $configs = pop @filenamelist;
  @cfglines = split /@@/, $configs;
  foreach $tline (@cfglines)
  {
    ($test, $cfg) = split /`/, $tline;
    $confighash{$test} = $cfg;
  }

  # acquire expected test results
  while ($tline !~ /^begin resultkey/) {$tline = <DATA>;}
  %expected = testme_makeexpecthash();

  # run the tests
  $limit = scalar(@filenamelist) - 2;   # 1st 2 aren't .ini files
  print "\nNumber of tests to run: <$limit>\n\n";
  for ($test=1; $test<=$limit; $test++)
  {
    # remember that this mode puts the (-count) results in a file
    system("perl $0 -testdiag -infile=$currdir/$testfile1 -inifile=$currdir/mwwwwtest$test.ini");
  }
  # the results file is also to be deleted
  push @filenamelist, $testoutfile;

  # get test scores
  %scores = testme_makescoreshash();  

  # check the scores
  for $test (sort keys %expected)
  {
    if (!exists($scores{$test}) or ($expected{$test} ne $scores{$test}))
    {
      print "FAILURE on test <$test> using config: <$confighash{$test}>\n";
      print "    Expected: $expected{$test}   Got: $scores{$test}\n\n";
      $havefailure = 1;
    }
  }
  if (!$havefailure) {print "PASSED all tests!\n\n";}

  # clean up
  for $file (@filenamelist)
  {
    if ((unlink "$currdir/$file") != 1) {print "Failure on deletion\n";}
  }
  exit;
}

__END__;

BEGIN TEST SECTION
test record 1
01490nam  2200385 a 450000100110000000300080001100600190001900700150003800800410
00530100017000940150015001110160019001260200027001450200033001720400021002050350
02000226050002600246082001700272245009600289260003200385300004300417504005300460
53301520051365000270066565000230069265000220071565000290073765000290076665000270
0795650002800822655002900850700003100879710001700910856017700927@@@@ebr2002404@@
@@CaPaEBR@@@@m        u        @@@@cr cn|||||||||@@@@001016s2000    enkac   sb  
  001 0 eng  @@@@  @@@z   99089569 @@@@  @@@aGBA0-65401@@@@7 @@@a0415188970@@@2U
k@@@@  @@@z0415188970 :@@@cNo price@@@@  @@@z0415188989(pbk.) :@@@cNo price@@@@ 
 @@@aCaPaEBR@@@cCaPaEBR@@@@  @@@a(OCoLC)50820497@@@@14@@@aGN799.C38@@@bC55 2000e
b@@@@04@@@a305.2309@@@221@@@@00@@@aChildren and material culture@@@h[electronic 
resource] /@@@cedited by Joanna Sofaer Derevenski.@@@@  @@@aLondon :@@@bRoutledg
e,@@@c2000.@@@@  @@@axvii, 225 p. :@@@bill., ports. ;@@@c26 cm.@@@@  @@@aInclude
s bibliographical references and indexes.@@@@  @@@aElectronic reproduction.@@@bP
alo Alto, Calif. :@@@cebrary,@@@d2005.@@@nAvailable via World Wide Web.@@@nAcces
s may be limited to ebrary affiliated libraries.@@@@ 0@@@aChildren, Prehistoric.
@@@@ 0@@@aChildren@@@xHistory.@@@@ 0@@@aMaterial culture.@@@@ 0@@@aIndustries, P
rehistoric.@@@@ 0@@@aArchaeology and history.@@@@ 0@@@aCivilization, Ancient.@@@
@ 0@@@aCivilization, Medieval.@@@@ 7@@@aElectronic books.@@@2local@@@@1 @@@aDere
venski, Joanna Sofaer.@@@@2 @@@aebrary, Inc.@@@@40@@@uhttp://libproxy.library.wm
ich.edu:2048/login?url=http://site.ebrary.com/lib/wmichlib/Doc?id=2002404@@@zAn 
electronic book accessible through the World Wide Web; click to view@@@@

test record 2
01329nam  22003254a 450000100110000000300080001100600190001900700150003800800410
00530100017000940200015001110200022001260400021001480350020001690500027001890820
01800216100002600234245007900260260004400339300007800383504006600461533015200527
65000320067965000320071165000190074365500290076270000180079171000170080985601770
0826@@@@ebr2002446@@@@CaPaEBR@@@@m        u        @@@@cr cn|||||||||@@@@000330s
2001    enkab   sb    001 0 eng  @@@@  @@@z   00038247 @@@@  @@@z0415198836@@@@ 
 @@@z0415198844 (pbk.)@@@@  @@@aCaPaEBR@@@cCaPaEBR@@@@  @@@a(OCoLC)50016763@@@@1
4@@@aQA76.9.C66@@@bD64 2001eb@@@@04@@@a303.48/33@@@221@@@@1 @@@aDodge, Martin,@@
@d1971-@@@@10@@@aMapping cyberspace@@@h[electronic resource] /@@@cMartin Dodge a
nd Rob Kitchin.@@@@  @@@aLondon ;@@@aNew York :@@@bRoutledge,@@@c2001.@@@@  @@@a
x, 260 p., 8 p. of plates :@@@bill. (some col.), maps (some col.) ;@@@c26 cm.@@@
@  @@@aIncludes bibliographical references (p. [230]-255) and index.@@@@  @@@aEl
ectronic reproduction.@@@bPalo Alto, Calif. :@@@cebrary,@@@d2005.@@@nAvailable v
ia World Wide Web.@@@nAccess may be limited to ebrary affiliated libraries.@@@@ 
0@@@aComputers and civilization.@@@@ 0@@@aCyberspace@@@xSocial aspects.@@@@ 0@@@
aCommunication.@@@@ 7@@@aElectronic books.@@@2local@@@@1 @@@aKitchin, Rob.@@@@2 
@@@aebrary, Inc.@@@@40@@@uhttp://libproxy.library.wmich.edu:2048/login?url=http:
//site.ebrary.com/lib/wmichlib/Doc?id=2002446@@@zAn electronic book accessible t
hrough the World Wide Web; click to view@@@@


begin testini
test1.ini`050|1|4|any|b|any|contains||55
test2.ini`050|*|*|any|b|any|contains||55
test3.ini`~050|1|4|any|b|any|contains||55
test4.ini`050|1|5|any|b|any|contains||55
test5.ini`050|1|~5|any|b|any|contains||55
test6.ini`050|~0|4|any|b|any|contains||55
test7.ini`655|*|*|any||books
test8.ini`655|*|*|any|~|turtle
test9.ini`655|*|*|any|c|Books 
test10.ini`655|*|*|any|c~|locaL
test11.ini`650|*|*|any|a|any|contains||Material
test12.ini`650|*|*|any|a|any|contains|~|Material
test13.ini`~650|*|*|any|a|any|contains||Material
test14.ini`650|*|*|first|a|any|contains||Children
test15.ini`650|*|*|last|a|any|contains||Children
test16.ini`650|*|*|any|a|all|contains||x
test17.ini`rlen:>2500
test18.ini`rlen:<2500
test19.ini`07:m
test20.ini`08: 
test21.ini`08:#
test22.ini`19:x
test23.ini`rlen:<2500.18:b
test24.ini`rlen:<2500.18:a|655|*|*|any|~|turtle
test25.ini`~rlen:<2500.18:a|655|*|*|any|~|turtle
end testini

# presently using test record 1 only

begin resultkey
1=1
2=1
3=0
4=0
5=1
6=1
7=1
8=1
9=0
10=1
11=1
12=1
13=0
14=1
15=0
16=0
17=0
18=1
19=1
20=1
21=1
22=0
23=0
24=1
25=0
end resultkey

END TEST SECTION

=head1 MARCWEEDER

Checks a MARC file for records matching a specified configuration.

=head2 Usage

   marcweeder   -config
     OR
   marcweeder   -infile=inputfilename
                -outfile=outputfilename  |  -count
              [ -inifile=inifilename ]
              [ -progpct ]

Supplying the sole parameter C<-config> puts marcweeder into config
assist mode, where it prompts you for the various configuration
parameters, and writes that information to the .ini file.
(Overwrites existing file of same name.)

In normal use, specify the name of a MARC file to be checked, as the
first parameter.

For the second parameter, enter C<-count> if all you want is counts of
matches. Else specify a filename, and marcweeder will copy records
matching the configuration into that file. Note: you will always get
counts.

By default, marcweeder gets configuration information from
marcweeder.ini in the current directory. You can specify a different
filename and location, if desired. In that case, the marcweeder.ini
file in the current directory will be ignored.

marcweeder indicates progress via a running count of records checked
(except for small files). Supplying the last optional parameter
C<-progpct> gives you a running % completed display. This method is
optional, as large files can cause a noticeable delay at startup
with this parameter.

Anything other than the filenames you supply must be entered as
shown above.

=head3 Assumption/Recommendation

It is assumed that marcweeder is called from a globally available
"wrapper" shell script. This shell script need only contain one 
executable line: 

 [path-to]marcweeder.pl $1 $2 $3 $4

The shell script should be on your path. This way, you can run
marcweeder by entering C<marcweeder parameters>. Otherwise you'll
need to enter C<perl [path-to]marcweeder.pl parameters>.

=head2 .ini File Configuration Overview

The .ini file contains three types of lines. There are comment lines, which
start with the "#" character, and blank lines. marcweeder ignores both of
these. Any other lines are considered to be config information.

=head3 Syntax for a field check:

 [~] [leaderstuff] 999 [~]ind1 [~]ind2 fieldwhich:{first|any|all|last]}
    [[~][c]] fielddata

=head3 Syntax for a subfield check:

 [~] [leaderstuff] 999 [~]ind1 [~]ind2 fieldwhich:{first|any|all|last}
    subfield subfieldwhich:{first|any|all|last}
             howmatch:{starts|contains|ends}
             [[~][c]] subfielddata

=head3 Syntax for checking the leader:

 [ [rlen:{>|<} len ] pos:val pos:val...]

Syntax is shown in expanded fashion for clarity. Square brackets [ ]
contain something optional. Curly brackets { } indicate you must
choose one of the contained items for that parameter. In actual use,
each specification will be entirely on one line; spaces could appear only in the
data being matched; each section is separated via the pipe "|"
character; and the C<which:...>, C<field:...>, C<subfield which:...>,
and C<howmatch:...> parts should consist entirely of B<one> of the
listed choices. See the I<Examples> section for real usage examples.

=head2 Configuration syntax details

=head3 Leader check syntax in detail

Leader checking is optional; omit this part if the leader does not matter.
You can supply a leader specification by itself, without any field
or subfield specification. Also, while in config-assist mode, while
you can enter multiple field and/or subfield specifications, you can
provide only one leader specification.

There can be one or two types of data checks for leader data. You must
always check for some position(s) having some value. As an option, you can
also check for record length.

A maximal leader check could look like this:

 rlen:>2390.05:a.06:b.07:c.08:#.09:3.17:4.18: .19:x

Within the leader part of a marcweeder matching specification,
individual parts are separated via the period "." character. (The leader
part is separated from the other parts of a marcweeder specification by
the pipe "|" character.) 

Each individual leader item is further separated via the colon ":"
character:

 leader_item:value

=head4 Record length

If you want to do record length checking, choose between looking for
records longer or shorter than a specified length. This example would
match only those records with a length of at least 2391:

 rlen:>2390

=head4 Positions and values

Positions are labelled with two digits. Values can be any single
character used in those positions. Only those leader
positions likely to be useful are available for checking.

 05:a.06:b.07:c.08:#.09:3.17:4.18: .19:x

In this example, every possible leader position will be checked for the
indicated value or character. Positions 5, 6, and 7 must contain the
characters a, b, and c, respectively. Positions 9 and 17 must contain the
characters 3 and 4 respectively. Position 19 must contain an "x".
Positions 8 and 18 must each contain a space " " character. Note that
a space value can be indicated by the space " " character, and also
by the pound/sharp "#" character commonly used for that.
Only those positions specified will be checked; you can skip those you
do not care about.


=head3 Field check syntax in detail

 [~] [leaderstuff] 999 [~]ind1 [~]ind2 fieldwhich:{first|any|all|last}
    [[~][c]] fielddata

Putting a tilde at the beginning of the line means to invert the match.
Use this to I<exclude> records matching what's specified.

Leader matching optionally is next and is described separately above, in
detail.

You must supply three digits specifying which field will be looked at.

Next are indicators 1 and 2. Entering an asterisk "*" in either one
means that that indicator will always be a match (never actually
checked). Preceding an indicator character with the tilde will match
that indicator whenever it is I<not> the character specified.

The C<fieldwhich> part consists solely of one of the four literal word
choices available. For C<first> and C<last>, only the first or last
occurrences, respectively, of this field will be checked. C<any> and
C<all> should also be obvious.

The next part must always be present, even if it's empty. It can contain
a "c", a tilde "~", or both. Using the "c" indicates a case-sensitive
match. Using the tilde results in a match if the field does I<not> have
this data.

The last part is the actual data to be checked for in the field.

=head3 Subfield check syntax in detail

 [~] [leaderstuff] 999 [~]ind1 [~]ind2 fieldwhich:{first|any|all|last}
    subfield subfieldwhich:{first|any|all|last}
             howmatch:{starts|contains|ends}
             [[~][c]] subfielddata

Putting a tilde at the beginning of the line means to invert the match.
Use this to I<exclude> records matching what's specified.

Leader matching optionally is next and is described separately above, in
detail.

You must supply three digits specifying which field will be looked at.

Next are indicators 1 and 2. Entering an asterisk "*" in either one
means that that indicator will always be a match (never actually
checked). Preceding an indicator character with the tilde will match
that indicator whenever it is I<not> the character specified.

The C<fieldwhich> part consists solely of one of the four literal word
choices available. For C<first> and C<last>, only the first or last
occurrences, respectively, of this field will be checked. C<any> and
C<all> should also be obvious.

(These first five parts of the syntax are the same for both field and
subfield checks.)

Provide the single character specifying the subfield.

The next section is the same as described above; one of the four
literal words specifying which subfield occurrence(s) to match.

The C<howmatch> section is similar: it consists solely of one of the
three literals to specify the kind of match. C<starts> means this
subfield's data must start with the data indicated; similarly C<ends>
means to end with. C<contains> means the data could be found anywhere
with the subfield's data.

The next part must always be present, even if it's empty. It can contain
a "c", a tilde "~", or both. Using the "c" indicates a case-sensitive
match. Using the tilde results in a match if the field does I<not> have
this data.

The last part is the actual data to be checked for in the subfield.

=head2 Examples

 rlen:<50000

Simple search for records that are not too long, i.e., less than
50,000 bytes.

 05:a

Look for all records that have an "a" in leader position 5.

 rlen:>24351.07:c.18:#

Look for records longer than the specified length, and they must have a
"c" in leader position 7 and leader position 18 must contain a space. 

 245|*|*|any||forest

Looks for I<forest> in a 245 field. We do not care about indicators,
nor which 245 field occurrence it is found in.

 050|1|4|any|b|any|contains|c|C55

Look in any 050 fields with indicators 1 and 4. See if any subfield b
has I<C55> anywhere in it, and letter case must match.

 245|1|*|any|b|first|starts||crime

Look in any 245 fields with first indicator 1. See if the first
subfield b starts with I<crime> or I<Crime>.

 003|1|2|first|EBR

Looks for 003 fields containing I<EBR>. It doesn't matter what you
specify for indicators with control fields. This will be ignored
since these fields don't have indicators.

 856|*|*|all|~|ebrary

Looks for electronic records that are not from I<ebrary>.

 100|*|*|all|a|all|contains|~|Alexander, George

Looks for books that are not authored by I<George Alexander>. Not that
we care for indicators either, here.

 ~260|*|*|all||Pantheon Books

Exclude records if field 260 indicates the publisher is I<Pantheon
Books>.

 rlen:<80000.06:x.19:b|610|*|*|first|easy

For records shorter than 80,000 bytes, the leader must have an "x"
in position 6 and a "b" in position 19. There must be a 610 field.
The first 610 field (if there's more than one) must contain the 
word "easy". We don't care about indicators. If the record we're
looking at meets these specifications, we have a match.

=head2 Additional information

=head3 Notes

Just because you can logically specify something doesn't mean it will
actually make sense in the context of a particular MARC field or
record.

If you're working with an interleaved file of bibs and holdings, you
could use the leader to differentiate, or pick out, just one type of
record if needed. Look at position 6.

You may wish to be cautious with the use of I<any> and I<all>. Think of
the use of "and" and "or" in spoken language. Sometimes you really mean
the B<opposite> of what you say.

You'll probably find it easier to work with marcweeder by keeping the
number of conditions specified low. That's highly recommended when
examining large files, in order to keep performance acceptable.
Besides, complexity breeds confusion.

marcweeder was written with bib records in mind, but should work with
any MARC record.

=head3 Code Credit

Most of the code in this program is mine, but the parts that actually
make a MARC record usable for this program were written by Paul
Hoffman of Fenway Libraries Online. I'd been thinking of creating a
program like this for a while, and seeing Paul's code for some other
MARC functionality is what inspired me to get to work creating
marcweeder. Thank you, Paul.

=head3 Requirements

Perl version 5.10 or newer.

=head3 Author

Written 2012 by Roy Zimmer
