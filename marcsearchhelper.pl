#!/usr/local/bin/perl
while (<STDIN>)
{
  if (/^001:/)
  {
    $c1 = $_;
    $f1 = 1;
  }
  else
  {
    if ($_ !~ /^LDR/)
    {
      if (/$ARGV[0]/g)
      {
        if ($f1)
        {
          print ">>$c1";
          $f1=0;
        }
        print ">>$_";
      }
    }
  }
}
