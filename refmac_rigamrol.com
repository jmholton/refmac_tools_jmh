#! /bin/tcsh -f
#
#   standardized refine-and-water-built protocol
#
set path = ( .. $path )

set pdbin = start.pdb
set mtzfile = refineme.mtz
set passalong = ""
foreach arg ( $* )
    if("$arg" =~ *.pdb) then
        set pdbin = "$arg"
        continue
    endif
    if("$arg" =~ *.mtz) then
        set mtzfile = "$arg"
        continue
    endif
    set passalong = ( $passalong $arg )
end
echo "$pdbin $mtzfile"

set test = `echo header | mtzdump hklin $mtzfile | egrep 'FreeR| FREE$' | wc -l`
if( ! $test ) then
   FreeRer.com $mtzfile
   set mtzfile = FreeRed.mtz
endif


set sigma = 6
set dist  = 1.8
cp $pdbin new.pdb
set round = `ls -1rt converge*.log |& awk '{print substr($0,9)+0}' | sort -g | tail -n 1`
if("$round" == "") set round = 0
foreach itr ( 1 2 3 4 5 )
  @ round = ( $round + 1 )
  cp new.pdb occme.pdb
  if(-s occme0.pdb) then
    cat occme0.pdb >! occme.pdb
    awk '/HOH/' new.pdb >> occme.pdb
  endif
  egrep -v "^occupancy" refmac_opts.txt >! temp$$
  mv temp$$ refmac_opts.txt
  refmac_occupancy_setup.com occme.pdb $passalong >> refmac_opts.txt
  converge_refmac.com new.pdb $mtzfile trials=10 append $passalong >! converge${round}.log
  rm new.pdb
  add_waters.com sigma=$sigma dist=$dist refmacout.pdb refmacout.mtz >! add_waters${round}.log
  set sigma = `echo $round | awk '{sigma=6-$1*0.5} sigma<3{sigma=3} {print sigma}'`
  # generates new.pdb
  if(! -e new.pdb) break
end
@ round = ( $round + 1 )
cp new.pdb occme.pdb
if(-s occme0.pdb) then
  cat occme0.pdb >! occme.pdb
  awk '/HOH/' new.pdb >> occme.pdb
endif
egrep -v "^occupancy" refmac_opts.txt >! temp$$
mv temp$$ refmac_opts.txt
refmac_occupancy_setup.com occme.pdb $passalong >> refmac_opts.txt
converge_refmac.com new.pdb $mtzfile trials=30 append $passalong >! converge${round}.log
set sigma = 6
set dist = 1.0
add_waters.com sigma=$sigma dist=$dist >! add_waters${round}.log

@ round = ( $round + 1 )
cp new.pdb occme.pdb
if(-s occme0.pdb) then
  cat occme0.pdb >! occme.pdb
  awk '/HOH/' new.pdb >> occme.pdb
endif
egrep -v "^occupancy" refmac_opts.txt >! temp$$
mv temp$$ refmac_opts.txt
refmac_occupancy_setup.com occme.pdb $passalong >> refmac_opts.txt
converge_refmac.com new.pdb $mtzfile trials=30 append $passalong >! converge${round}.log



