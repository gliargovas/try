#!/bin/bash

export TRY_TOP=${TRY_TOP:-$(git rev-parse --show-toplevel --show-superproject-working-tree)}
export WORKING_DIR="$TRY_TOP/test"
export RESOURCE_DIR="$WORKING_DIR/resources"
export MISC_SCRIPT_DIR="$WORKING_DIR/misc"

echo "=================| Try Tests |==================="
echo "Test directory:           $WORKING_DIR"
echo "Resource directory:       $RESOURCE_DIR"

## Set the DEBUG env variable to see detailed output
DEBUG=${DEBUG:-0}


bash="bash"
try="$TRY_TOP/try"

try_workspace="$TRY_TOP/test/try_workspace"
test_workspace="$TRY_TOP/test/test_workspace"

# Results saved here
output_dir="$TRY_TOP/test/results"

echo "Bash test workspace:      $try_workspace"
echo "try test workspace:       $test_workspace"
echo "Results saved at:         $output_dir"
echo "================================================="

# Clear previous test results
rm -rf "$output_dir"
mkdir -p "$output_dir"
touch "$output_dir/result_status"

cleanup()
{
    rm -rf "$try_workspace"
    mkdir "$try_workspace"
    rm -rf "$test_workspace"
    mkdir "$test_workspace"
}

run_test()
{
    cleanup
    local test=$1

    if [ "$(type -t $test)" != "function" ]; then
        echo "$test is not a function!   FAIL"
        return 1
    fi

    echo -n "Running $test..."

    # cd $try_workspace
    $test "$bash" "$test_workspace"
    test_bash_ec=$?
    # Run test
    $test "$try" "$try_workspace"
    test_try_ec=$?
    # Check test EC
    
    diff -q "$test_workspace/" "$try_workspace/" > /dev/null
    test_diff_ec=$?
    if [ $test_diff_ec -ne 0 ]; then
        echo -n " (!) output mismatch"
        echo "$test are not identical" >> $output_dir/result_status
        echo -e '\t\tFAIL'
    else
        if [ $test_bash_ec != $test_try_ec ]; then
            echo -n " (!) EC mismatch"
            echo "$test are not identical" >> $output_dir/result_status
            echo -e '\t\tFAIL'
        else
            echo -ne '\t\t\t'
            echo "$test are identical" >> $output_dir/result_status
            echo -e '\tOK'
        fi
    fi
}

test1()
{
    local shell=$1
    cp $RESOURCE_DIR/* "$2/"
    # Will always commit the result in case of try
    yes 2>/dev/null | $shell gunzip $2/file.txt.gz
}

# We run all tests composed with && to exit on the first that fails
if [ "$#" -eq 0 ]; then 
    run_test test1

else
    for testname in $@
    do
        run_test "$testname" "$2"
    done
fi

if type lsb_release > /dev/null ; then
   distro=$(lsb_release -i -s)
elif [ -e /etc/os-release ] ; then
   distro=$(awk -F= '$1 == "ID" {print $2}' /etc/os-release)
fi

distro=$(printf '%s\n' "$distro" | LC_ALL=C tr '[:upper:]' '[:lower:]')
# do different things depending on distro
case "$distro" in
    freebsd*)  
        # change sed to gsed
        sed () {
            gsed $@
        }
        ;;
    *)
        ;;
esac

echo -e "\n====================| Test Summary |====================\n"
echo "> Below follow the identical outputs:"
grep "are identical" "$output_dir"/result_status | awk '{print $1}' | tee $output_dir/passed.log

echo "> Below follow the non-identical outputs:"     
grep "are not identical" "$output_dir"/result_status | awk '{print $1}' | tee $output_dir/failed.log
echo "========================================================"
TOTAL_TESTS=$(cat "$output_dir"/result_status | wc -l | xargs)
PASSED_TESTS=$(grep -c "are identical" "$output_dir"/result_status)
echo "Summary: ${PASSED_TESTS}/${TOTAL_TESTS} tests passed." | tee $output_dir/results.log
echo "========================================================"