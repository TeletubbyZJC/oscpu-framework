#include <unistd.h>
#include <getopt.h>

#include <verilated_vcd_c.h>
#include <verilated.h>
#include <VysyxSoCFull.h>

extern "C"
{
  void flash_init(const char *img);
}

class Emulator
{
public:
  Emulator(int argc, char *argv[])
  {
    parseArgs(argc, argv);

    if (args.image == nullptr)
      throw "Image file unspecified. Use -i to provide the image of flash";
    flash_init(args.image);
    printf("Flash initialized with \"%s\"\n", args.image);

    printf("Initializing DUT...\n");
    dut_ptr = new VysyxSoCFull;
    dut_ptr->clock = 0;
    dut_ptr->reset = 1;
    dut_ptr->eval();
    dut_ptr->clock = 1;
    dut_ptr->reset = 1;
    dut_ptr->eval();
    dut_ptr->reset = 0;

    if (args.dumpWave)
    {
      Verilated::traceEverOn(true);
      printf("Enabling waves ...\n");
      fp = new VerilatedVcdC;
      dut_ptr->trace(fp, 1);
      fp->open("vlt_dump.vcd");
      fp->dump(0);
    }
  }
  ~Emulator()
  {
    if (args.dumpWave)
    {
      fp->close();
      delete fp;
    }
  }

  void step()
  {
    dut_ptr->clock = 1;
    dut_ptr->eval();
    if (args.dumpWave)
      fp->dump(++cycle);

    dut_ptr->clock = 0;
    dut_ptr->eval();
    if (args.dumpWave)
      fp->dump(++cycle);
  }

private:
  void parseArgs(int argc, char *argv[])
  {

    int long_index;
    const struct option long_options[] = {
        {"dump-wave", 0, NULL, 0},
        {"image", 1, NULL, 'i'},
        {"help", 0, NULL, 'h'},
        {0, 0, NULL, 0}};

    int o;
    while ((o = getopt_long(argc, const_cast<char *const *>(argv),
                            "-hi:", long_options, &long_index)) != -1)
    {
      switch (o)
      {
      case 0:
        switch (long_index)
        {
        case 0:
          args.dumpWave = true;
          continue;
        }
        // fall through
      default:
        print_help(argv[0]);
        exit(0);
      case 'i':
        args.image = optarg;
        break;
      }
    }

    Verilated::commandArgs(argc, argv);
  }
  static inline void print_help(const char *file)
  {
    printf("Usage: %s [OPTION...]\n", file);
    printf("\n");
    printf("  -i, --image=FILE           run with this image file\n");
    printf("      --dump-wave            dump waveform when log is enabled\n");
    printf("  -h, --help                 print program help info\n");
    printf("\n");
  }

  int cycle = 0;
  struct Args
  {
    bool dumpWave = false;
    const char *image = nullptr;
  } args;

  VysyxSoCFull *dut_ptr = nullptr;
  VerilatedVcdC *fp = nullptr;
};
