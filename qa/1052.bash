# Note:
# 	This ONLY works if it is run using bash, not sh
#
# PCP QA Test No. 1052
# Exercise the JSON PMDA.
#
# Copyright (c) 2015 Red Hat.
#

seq=`basename $0 .bash`
echo "QA output created by $seq"

. ./common.python

python_path=`which $python`
pmda_path="$PCP_PMDAS_DIR/json"
pmda_script="${pmda_path}/pmdajson.python"
pmda_config="${pmda_path}/config.json"
ceph_script="${pmda_path}/generate_ceph_metadata"
qa_dir=`pwd`
json_qa_dir="${qa_dir}/json"
pmda_config_dir="${PCP_VAR_DIR}/config/pmda"
pmda_saved_config_dir="${pmda_config_dir}/pmdajson.$seq"
test -f "$pmda_script" || _notrun "pmdajson not installed"
$python -c "from pcp import pmda" >/dev/null 2>&1
[ $? -eq 0 ] || _notrun "python pcp pmda module not installed"
$python -c "import jsonpointer" >/dev/null 2>&1
[ $? -eq 0 ] || _notrun "python jsonpointer module not installed"
$python -c "import six" >/dev/null 2>&1
[ $? -eq 0 ] || _notrun "python six module not installed"

status=1	# failure is the default!
$sudo rm -rf $tmp.* $seq.full
mkdir $tmp
chmod ugo+rwx $tmp
cd $tmp

# We need a bit more interaction with dbpmda than other tests do, so
# create 2 named pipes (FIFOs). This allows us to send dbpmda some
# commands, do some shell commands, then send the same dbpmda session
# more commands.
fifo_in="${tmp}/fifo_in"
fifo_out="${tmp}/fifo_out"
$sudo mkfifo ${fifo_in} ${fifo_out}
$sudo chmod 666 ${fifo_in} ${fifo_out}

_needclean=true
trap "cleanup; exit \$status" 0 1 2 3 15

# Notice in _drain_output() we are reading from fd 4, which will be
# set up later to point one of the fifos we created above.
_drain_output()
{
    quit=0
    while [ $quit -eq 0 ]; do
	# detect failure, but have a last round
	read -u 4 -t 1 output || quit=1
	echo "$output" | _filter
    done
}

# We have to sort the output of certain commands (like "children"),
# since the order of the output depends on python internal ordering.
_drain_output_sorted()
{
    _drain_output | LC_COLLATE=POSIX sort
}

_filter()
{
    tee -a $here/$seq.full | \
    sed \
	-e "s;$PCP_PMDAS_DIR;\$PCP_PMDAS_DIR;" \
        -e '/pmResult/s/ .* numpmid/ ... numpmid/' \
        -e '/[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/s/[^ ]*/TIMESTAMP/' \
	-e "s;$python_path;\$PCP_PYTHON_PROG;" \
	-e "s;$python;python;" \
	-e 's;137.3.[0-9][0-9]*;137.3.ID;' \
    #end
}

_filter2()
{
    tee -a $here/$seq.full | \
    sed \
	-e '2,$s/^\([0-9][0-9]*\) [0-9][0-9]* /\1 TIMESTAMP /'
}

cleanup()
{
    cd $here
    if $_needclean; then
	_needclean=false
        _restore_config $PCP_PMCDCONF_PATH
	if [ -f ${pmda_config}.$seq ]; then
	    _restore_config ${pmda_config}
	fi

	# Remove the newly created indom cache files and restore any
	# old indom cache files.
	$sudo rm -f ${pmda_config_dir}/${domain}.*
	if [ -d ${pmda_saved_config_dir} ]; then
	    $sudo mv ${pmda_saved_config_dir}/* ${pmda_config_dir}/
	    $sudo rm -rf ${pmda_saved_config_dir}
	fi
    fi
    $sudo rm -rf $tmp $tmp.* json.log
}

domain=137
test="$here/json"

# Copy the pmcd config file to restore state later.
_save_config $PCP_PMCDCONF_PATH

# Ditto for JSON pmda config.
if [ -f ${pmda_config} ]; then
    _save_config ${pmda_config}
fi

# We want to get any JSON pmda indom cache files out of the way, so we
# start with a clean slate. We'll restore these at the end.
if [ -f "${pmda_config_dir}/${domain}.0" ]; then
    $sudo rm -rf ${pmda_saved_config_dir}
    $sudo mkdir ${pmda_saved_config_dir}
    $sudo mv ${pmda_config_dir}/${domain}.* ${pmda_saved_config_dir}/
fi

# Create a new JSOM pmda config file and install it
cat > ${tmp}/config.json << EOF
{
    "directory_list" : [
	"${tmp}"
    ]
}
EOF
$sudo cp ${tmp}/config.json ${pmda_config}

# Create some JSON data/metadata files.
#
# SRC1 is a basic JSON data/metadata files.
SRC1_METADATA="${tmp}/s1_metadata.json"
SRC1_DATA1="${tmp}/s1_data1.json"
SRC1_DATA2="${tmp}/s1_data2.json"
cat > ${SRC1_METADATA} <<EOF
{
  "metrics": [
    {
      "name": "string",
      "pointer": "/string",
      "type": "string",
      "description": "Test string"
    },
    {
      "name": "value",
      "pointer": "/value",
      "type": "integer",
      "description": "Integer value",
      "semantics": "instantaneous"
    },
    {
      "name": "counter",
      "pointer": "/counter",
      "type": "double",
      "description": "double counter",
      "semantics": "counter"
    },
    {
      "name": "discrete",
      "pointer": "/discrete",
      "type": "integer",
      "description": "discrete integer",
      "semantics": "discrete"
    }
  ]
}
EOF
cat > ${SRC1_DATA1} <<EOF
{
  "string": "original value",
  "value": 0,
  "counter": 5,
  "discrete": 7
}
EOF
cat > ${SRC1_DATA2} <<EOF
{
  "string": "new value",
  "value": 99,
  "counter": 10,
  "discrete": 14
}
EOF

# SRC2 is more complicated, and has an array.
SRC2_METADATA="${tmp}/s2_metadata.json"
SRC2_DATA1="${tmp}/s2_data1.json"
SRC2_DATA2="${tmp}/s2_data2.json"
SRC2_DATA3="${tmp}/s2_data3.json"
SRC2_DATA4="${tmp}/s2_data4.json"
cat > ${SRC2_METADATA} <<EOF
{
  "metrics": [
    {
      "name": "array_data",
      "pointer": "/array_data",
      "type": "array",
      "index": "/__id",
      "metrics": [
        {
          "name": "count",
          "pointer": "/count",
          "type": "integer"
        },
        {
          "name": "value",
          "pointer": "/value",
          "type": "integer"
        },
        {
          "name": "counter",
          "pointer": "/counter",
          "type": "double",
          "semantics": "counter"
        }
      ]
    }
  ]
}
EOF
cat > ${SRC2_DATA1} <<EOF
{
  "array_data": [
    {
      "__id": "first",
      "count": 0,
      "value": 1024,
      "counter": 3
    },
    {
      "__id": "second",
      "count": 99,
      "value": 2048,
      "counter": 5
    }
  ]
}
EOF
cat > ${SRC2_DATA2} <<EOF
{
  "array_data": [
    {
      "__id": "third",
      "count": 3,
      "value": 3072,
      "counter": 7
    },
    {
      "__id": "second",
      "count": 100,
      "value": 2049,
      "counter": 10
    }
  ]
}
EOF
cat > ${SRC2_DATA3} <<EOF
{
  "array_data": [
    {
      "__id": "first",
      "count": 1,
      "value": 1025,
      "counter": 6
    },
    {
      "__id": "fourth",
      "count": 4,
      "value": 999,
      "counter": 13
    }
  ]
}
EOF
cat > ${SRC2_DATA4} <<EOF
{
  "array_data": [
    {
      "__id": "first",
      "count": 2,
      "value": 1026,
      "counter": 9
    }
  ]
}
EOF

#
# real QA test starts here
#

pmns_root="${tmp}/json.root"
PCP_PYTHON_PMNS=root $python "$pmda_script" > ${pmns_root}

# Start dbpmda in the background, redirecting its stdin/stdout to the
# fifos.
cd $here	# create pmda log file somewhere safe (for debugging)
$sudo dbpmda -n ${pmns_root} -e <${fifo_in} >${fifo_out} 2>&1 &

# Open fd 3 for write and fd 4 for read. Note that we need to avoid
# closing either fifo below, so we have to be careful with redirects.
exec 3>${fifo_in} 4<${fifo_out}

# Check to see if the 'nsources' static metric is present.
cat >&3 <<EOF
open pipe $python_path $pmda_script
getdesc on
desc json.nsources
fetch json.nsources
EOF
_drain_output

cat >&3 <<EOF
children json
EOF
_drain_output_sorted

# Now, let's add a JSON data source.
mkdir ${tmp}/s1
cp $SRC1_METADATA ${tmp}/s1/metadata.json
cp $SRC1_DATA1 ${tmp}/s1/data.json

# On this fetch, the 'nsources' static metric should be increased and
# the new data source should be present.
cat >&3 <<EOF
fetch json.nsources
EOF

cat >&3 <<EOF
children json
children json.s1
EOF
_drain_output_sorted

cat >&3 <<EOF
desc json.s1.counter
desc json.s1.discrete
fetch json.s1.string
fetch json.s1.value
fetch json.s1.counter
fetch json.s1.discrete
EOF
_drain_output

# Now update the JSON data for the source.
cp $SRC1_DATA2 ${tmp}/s1/data.json

# On this fetch, the data source variables should have their new values.
cat >&3 <<EOF
fetch json.nsources
fetch json.s1.string
fetch json.s1.value
fetch json.s1.counter
fetch json.s1.discrete
EOF
_drain_output

# Add the 2nd JSON data source.
mkdir ${tmp}/s2
cp $SRC2_METADATA ${tmp}/s2/metadata.json
cp $SRC2_DATA1 ${tmp}/s2/data.json

# On this fetch, the 'nsources' static metric should be increased and
# the new data source should be present.
cat >&3 <<EOF
fetch json.nsources
EOF
_drain_output

cat >&3 <<EOF
children json
children json.s1
children json.s2
EOF
_drain_output_sorted

cat >&3 <<EOF
instance $domain.0
desc json.s2.array_data.counter
fetch json.s2.array_data.count
fetch json.s2.array_data.value
fetch json.s2.array_data.counter
EOF
_drain_output

# Let's test proper indom support with the 2nd source. First, find out
# what the current indom state looks like.
cat ${pmda_config_dir}/${domain}.4 | _filter2
cat >&3 <<EOF
instance $domain.4
EOF
_drain_output

# Copy a new data file in and see how the instance values change. The
# instance command just returns "active" instances, not all instances.
cp $SRC2_DATA2 ${tmp}/s2/data.json
cat >&3 <<EOF
fetch json.s2.array_data.count
fetch json.s2.array_data.value
fetch json.s2.array_data.counter
instance $domain.4
EOF
_drain_output
# We should see all instances by looking at the indom cache file.
cat ${pmda_config_dir}/${domain}.4 | _filter2

# Let's try another indom test. This data file reuses an inactive
# instance and adds a new one.
cp $SRC2_DATA3 ${tmp}/s2/data.json
cat >&3 <<EOF
fetch json.s2.array_data.count
fetch json.s2.array_data.value
fetch json.s2.array_data.counter
instance $domain.4
EOF
_drain_output
# We should see all instances by looking at the indom cache file.
cat ${pmda_config_dir}/${domain}.4 | _filter2

# Let's try another indom test. This data file just reuses an
# instance.
cp $SRC2_DATA4 ${tmp}/s2/data.json
cat >&3 <<EOF
fetch json.s2.array_data.count
fetch json.s2.array_data.value
fetch json.s2.array_data.counter
instance $domain.4
EOF
_drain_output
# We should see all instances by looking at the indom cache file.
cat ${pmda_config_dir}/${domain}.4 | _filter2

# Let's test the ceph support by running the 'generate_ceph_metadata'
# script on some canned data.
mkdir -p ${tmp}/ceph
cp ${json_qa_dir}/ceph_data1.json ${tmp}/ceph/data.json
# Use the generate_ceph_metadata script to convert the ceph schema
# into metadata.
$python ${ceph_script} -o ${tmp}/ceph/metadata.json -t ${json_qa_dir}/ceph_schema1.json

# On this fetch, the 'nsources' static metric should be increased and
# the new data source should be present. Notice we aren't grabbing all
# the metrics from the ceph source, just a couple.
cat >&3 <<EOF
fetch json.nsources
EOF
_drain_output

cat >&3 <<EOF
children json
children json.s1
children json.s2
children json.ceph
EOF
_drain_output_sorted

cat >&3 <<EOF
instance $domain.0
fetch json.ceph.filestore.journal_wr_bytes.sum
fetch json.ceph.osd.stat_bytes
EOF
_drain_output

# Other things to test:
# - 'prefix' directive
# - 'data-exec' directive

# Tell dbpmda to quit.
cat >&3 <<EOF
quit
EOF
_drain_output

# Wait for dbpmda to quit.
wait

cat json.log >>$here/$seq.full

status=0
exit
