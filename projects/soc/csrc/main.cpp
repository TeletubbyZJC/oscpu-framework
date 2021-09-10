#include <cstdio>
#include <signal.h>

#include "verilated.h" //Defines common routines
#include "VysyxSoCFull.h"

#include <emu.h>

static int signal_received = 0;

void sig_handler(int signo)
{
    if (signal_received != 0)
    {
        puts("SIGINT received, forcely shutting down.\n");
        _exit(0);
    }
    puts("SIGINT received, gracefully shutting down...\n");
    signal_received = signo;
}

static Emulator *emu = nullptr;
void release()
{
    if (emu != nullptr)
        delete emu;
}

int main(int argc, char *argv[])
{
    printf("Emu compiled at %s, %s\n", __DATE__, __TIME__);

    if (signal(SIGINT, sig_handler) == SIG_ERR)
    {
        printf("can't catch SIGINT\n");
    }
    atexit(release);

    emu = new Emulator(argc, argv);
    while (!Verilated::gotFinish() && signal_received == 0)
    {
        emu->step();
    }

    return 0;
}
