#!/bin/bash

VERSION="1.0"

help() {
    echo "Version v"$VERSION
    echo "Usage:"
    echo "build.sh [-e project_name] [-b] [-t top_file] [-s] [-a parameters_list] [-f] [-l] [-g] [-w] [-c] [-d] [-m] [-r test_cases] [-v parameters_list] [-y]"
    echo "Description:"
    echo "-e: Specify a example project. For example: -e counter. If not specified, the default directory \"cpu\" will be used."
    echo "-b: Build project using verilator and make tools automatically. It will generate the \"build_test\" subfolder under the project directory."
    echo "-t: Specify a file as verilog top file. If not specified, the default filename \"top.v\" will be used."
    echo "-s: Run simulation program. Use the \"build_test\" folder as work path."
    echo "-a: Parameters passed to the simulation program. For example: -a \"1 2 3 ......\". Multiple parameters require double quotes."
    echo "-f: C++ compiler arguments for makefile. For example: -f \"-DGLOBAL_DEFINE=1 -ggdb3\". Multiple parameters require double quotes."
    echo "-l: C++ linker arguments for makefile. For example: -l \"-ldl -lm\". Multiple parameters require double quotes."
    echo "-g: Debug the simulation program with GDB."
    echo "-w: Open the latest waveform file(.vcd) using gtkwave under work path. Use the \"build_test\" folder as work path."
    echo "-c: Delete \"build\" and \"build_test\" folders under the project directory."
    echo "-r: Run all test cases of the specified directory in the \"bin\" directory. For example: -r \"case1 case2\"."
    echo "-v: Parameters passed to verilator. For example: -v '--timescale \"1ns/1ns\"'"
    exit 0
}

create_soft_link() {
    mkdir ${1} 1>/dev/null 2>&1
    find -L ${1} -type l -delete
    FILES=`eval "find ${2} -mindepth ${4} -maxdepth ${5} -name ${3}"`
    for FILE in ${FILES[@]}
    do
        eval "ln -s \"`realpath --relative-to="${1}" "$FILE"`\" \"${1}/${FILE##*/}\" 1>/dev/null 2>&1"
    done
}

create_bin_soft_link() {
    find -L $BUILD_PATH -maxdepth 1 -type l -delete
    FOLDERS=`find bin -mindepth 1 -maxdepth 1 -type d`
    for FOLDER in ${FOLDERS[@]}
    do
        SUBFOLDER=${FOLDER##*/}
        eval "ln -s \"`realpath --relative-to="$BUILD_PATH" "$OSCPU_PATH/$FOLDER"`\" \"$BUILD_PATH/${FOLDER##*/}\" 1>/dev/null 2>&1"
    done

    # create soft link ($BUILD_PATH/*.bin -> $OSCPU_PATH/$BIN_FOLDER/*.bin). Why? Because of laziness!
    create_soft_link $BUILD_PATH $OSCPU_PATH/$BIN_FOLDER \"*.bin\" 1 1
}

compile_chisel() {
    if [[ -f $PROJECT_PATH/build.sc ]]; then
        cd $PROJECT_PATH
        mkdir vsrc 1>/dev/null 2>&1
        mill -i oscpu.runMain TopMain -td vsrc
        if [ $? -ne 0 ]; then
            echo "Failed to compile chisel!!!"
            exit 1
        fi
        cd $OSCPU_PATH
    fi
}

build_proj() {
    compile_chisel

    cd $PROJECT_PATH

    # get all .cpp files
    CSRC_LIST=`find -L $PROJECT_PATH/$CSRC_FOLDER -name "*.cpp"`
    for CSRC_FILE in ${CSRC_LIST[@]}
    do
        CSRC_FILES="$CSRC_FILES $CSRC_FILE"
    done
    
    # get all vsrc subfolders
    VSRC_SUB_FOLDER=`find -L $VSRC_FOLDER -type d`
    for SUBFOLDER in ${VSRC_SUB_FOLDER[@]}
    do
        INCLUDE_VSRC_FOLDERS="$INCLUDE_VSRC_FOLDERS -I$SUBFOLDER"
    done
    INCLUDE_VSRC_FOLDERS="$INCLUDE_VSRC_FOLDERS -I$YSYXSOC_HOME/ysyx/ram"

    # get all csrc subfolders
    CSRC_SUB_FOLDER=`find -L $PROJECT_PATH/$CSRC_FOLDER -type d`
    for SUBFOLDER in ${CSRC_SUB_FOLDER[@]}
    do
        INCLUDE_CSRC_FOLDERS="$INCLUDE_CSRC_FOLDERS -I$SUBFOLDER"
    done

    # compile
    mkdir $BUILD_FOLDER 1>/dev/null 2>&1
    eval "verilator --x-assign unique --cc --exe --trace --assert -O3 $VERILATORFLAGS -CFLAGS \"-std=c++11 -Wall $INCLUDE_CSRC_FOLDERS $CFLAGS\" $LDFLAGS -o $PROJECT_PATH/$BUILD_FOLDER/$EMU_FILE \
        -Mdir $PROJECT_PATH/$BUILD_FOLDER/emu-compile $INCLUDE_VSRC_FOLDERS --build $V_TOP_FILE $CSRC_FILES"
    if [ $? -ne 0 ]; then
        echo "Failed to run verilator!!!"
        exit 1
    fi

    cd $OSCPU_PATH
}

# Initialize variables
OSCPU_PATH=$(dirname $(readlink -f "$0"))
MYINFO_FILE=$OSCPU_PATH"/myinfo.txt"
EMU_FILE="emu"
PROJECT_FOLDER="cpu"
BUILD_FOLDER="build"
VSRC_FOLDER="vsrc"
CSRC_FOLDER="csrc"
BIN_FOLDER="bin"
BUILD="false"
V_TOP_FILE="top.v"
SIMULATE="false"
CHECK_WAVE="false"
CLEAN="false"
PARAMETERS=
CFLAGS=
LDFLAGS=
GDB="false"
LIBRARIES_FOLDER="libraries"
NEMU_PATH=$LIBRARIES_FOLDER"/NEMU"
TEST_CASES=
VERILATORFLAGS=

# Check parameters
while getopts 'he:bt:sa:f:l:gwcr:v:' OPT; do
    case $OPT in
        h) help;;
        e) PROJECT_FOLDER="$OPTARG";;
        b) BUILD="true";;
        t) V_TOP_FILE="$OPTARG";;
        s) SIMULATE="true";;
        a) PARAMETERS="$OPTARG";;
        f) CFLAGS="$OPTARG";;
        l) LDFLAGS="$OPTARG";;.
        g) GDB="true";;
        w) CHECK_WAVE="true";;
        c) CLEAN="true";;
        r) TEST_CASES="$OPTARG";;
        v) VERILATORFLAGS="$OPTARG";;
        ?) help;;
    esac
done

[[ $LDFLAGS ]] && LDFLAGS="-LDFLAGS "\"$LDFLAGS\"

PROJECT_PATH=$OSCPU_PATH/projects/$PROJECT_FOLDER
BUILD_PATH=$PROJECT_PATH/$BUILD_FOLDER

# Get id and name
ID=`sed '/^ID=/!d;s/.*=//' $MYINFO_FILE`
NAME=`sed '/^Name=/!d;s/.*=//' $MYINFO_FILE`
if [[ ${#ID} -le 7 ]] || [[ ${#NAME} -le 1 ]]; then
    echo "Please fill your information in myinfo.txt!!!"
    exit 1
fi
ID="${ID##*\r}"
NAME="${NAME##*\r}"

# Clean
if [[ "$CLEAN" == "true" ]]; then
    rm -rf $PROJECT_PATH/$BUILD_FOLDER $PROJECT_PATH/out
    exit 0
fi

# Build project
if [[ "$BUILD" == "true" ]]; then
    [[ -d $BUILD_PATH ]] && find $BUILD_PATH -type l -delete
    build_proj

    #git commit
    if [[ ! -f $OSCPU_PATH/.no_commit ]]; then
        git add . -A --ignore-errors
        (echo $NAME && echo $ID && hostnamectl && uptime) | git commit -F - -q --author='tracer-oscpu2021 <tracer@oscpu.org>' --no-verify --allow-empty 1>/dev/null 2>&1
        sync
    fi
fi

# Simulate
if [[ "$SIMULATE" == "true" ]]; then
    create_bin_soft_link

    cd $BUILD_PATH
    
    # run simulation program
    echo "Simulating..."
    [[ "$GDB" == "true" ]] && gdb -s $EMU_FILE --args ./$EMU_FILE $PARAMETERS || ./$EMU_FILE $PARAMETERS

    if [ $? -ne 0 ]; then
        echo "Failed to simulate!!!"
        FAILED="true"
    fi

    cd $OSCPU_PATH
fi

# Check waveform
if [[ "$CHECK_WAVE" == "true" ]]; then
    cd $BUILD_PATH
    WAVE_FILE=`ls -t | grep .vcd | head -n 1`
    if [ -n "$WAVE_FILE" ]; then
        gtkwave $WAVE_FILE
        if [ $? -ne 0 ]; then
            echo "Failed to run gtkwave!!!"
            exit 1
        fi
    else
        echo "*.vcd file does not exist!!!"
    fi
    
    cd $OSCPU_PATH
fi

[[ "$FAILED" == "true" ]] && exit 1

# Run all
if [[ -n $TEST_CASES ]]; then
    create_bin_soft_link

    cd $BUILD_PATH

    mkdir log 1>/dev/null 2>&1
    for FOLDER in ${TEST_CASES[@]}
    do
        BIN_FILES=`eval "find $FOLDER -mindepth 1 -maxdepth 1 -regex \".*\.\(bin\)\""`
        for BIN_FILE in $BIN_FILES; do
            FILE_NAME=`basename ${BIN_FILE%.*}`
            printf "[%30s] " $FILE_NAME
            LOG_FILE=log/$FILE_NAME-log.txt
            ./$EMU_FILE -i $BIN_FILE &> $LOG_FILE
            if (grep 'HIT GOOD TRAP' $LOG_FILE > /dev/null) then
                echo -e "\033[1;32mPASS!\033[0m"
                rm $LOG_FILE
            else
                echo -e "\033[1;31mFAIL!\033[0m see $BUILD_PATH/$LOG_FILE for more information"
            fi
        done
    done

    cd $OSCPU_PATH
fi
