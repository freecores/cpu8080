#include "isim/work/cpu__tbw/cpu__tbw.h"
#include "isim/work/glbl/glbl.h"
static const char * HSimCopyRightNotice = "Copyright 2004-2005, Xilinx Inc. All rights reserved.";


#include "work/cpu__tbw/cpu__tbw.h"
static HSim__s6* IF0(HSim__s6 *Arch,const char* label,int nGenerics, 
va_list vap)
{
    HSim__s6 *blk = new workMcpu__tbw(label); 
    return blk;
}


#include "work/alu/alu.h"
static HSim__s6* IF1(HSim__s6 *Arch,const char* label,int nGenerics, 
va_list vap)
{
    HSim__s6 *blk = new workMalu(label); 
    return blk;
}


#include "work/selectone/selectone.h"
static HSim__s6* IF2(HSim__s6 *Arch,const char* label,int nGenerics, 
va_list vap)
{
    HSim__s6 *blk = new workMselectone(label); 
    return blk;
}


#include "work/select/select.h"
static HSim__s6* IF3(HSim__s6 *Arch,const char* label,int nGenerics, 
va_list vap)
{
    HSim__s6 *blk = new workMselect(label); 
    return blk;
}


#include "work/rom/rom.h"
static HSim__s6* IF4(HSim__s6 *Arch,const char* label,int nGenerics, 
va_list vap)
{
    HSim__s6 *blk = new workMrom(label); 
    return blk;
}


#include "work/ram/ram.h"
static HSim__s6* IF5(HSim__s6 *Arch,const char* label,int nGenerics, 
va_list vap)
{
    HSim__s6 *blk = new workMram(label); 
    return blk;
}


#include "work/intcontrol/intcontrol.h"
static HSim__s6* IF6(HSim__s6 *Arch,const char* label,int nGenerics, 
va_list vap)
{
    HSim__s6 *blk = new workMintcontrol(label); 
    return blk;
}


#include "work/cpu8080/cpu8080.h"
static HSim__s6* IF7(HSim__s6 *Arch,const char* label,int nGenerics, 
va_list vap)
{
    HSim__s6 *blk = new workMcpu8080(label); 
    return blk;
}


#include "work/testbench/testbench.h"
static HSim__s6* IF8(HSim__s6 *Arch,const char* label,int nGenerics, 
va_list vap)
{
    HSim__s6 *blk = new workMtestbench(label); 
    return blk;
}


#include "work/glbl/glbl.h"
static HSim__s6* IF9(HSim__s6 *Arch,const char* label,int nGenerics, 
va_list vap)
{
    HSim__s6 *blk = new workMglbl(label); 
    return blk;
}

class _top : public HSim__s6 {
public:
    _top() : HSim__s6(false, "_top", "_top", 0, 0, HSim::VerilogModule) {}
    HSimConfigDecl * topModuleInstantiate() {
        HSimConfigDecl * cfgvh = 0;
        cfgvh = new HSimConfigDecl("default");
        (*cfgvh).addVlogModule("cpu_tbw", (HSimInstFactoryPtr)IF0);
        (*cfgvh).addVlogModule("alu", (HSimInstFactoryPtr)IF1);
        (*cfgvh).addVlogModule("selectone", (HSimInstFactoryPtr)IF2);
        (*cfgvh).addVlogModule("select", (HSimInstFactoryPtr)IF3);
        (*cfgvh).addVlogModule("rom", (HSimInstFactoryPtr)IF4);
        (*cfgvh).addVlogModule("ram", (HSimInstFactoryPtr)IF5);
        (*cfgvh).addVlogModule("intcontrol", (HSimInstFactoryPtr)IF6);
        (*cfgvh).addVlogModule("cpu8080", (HSimInstFactoryPtr)IF7);
        (*cfgvh).addVlogModule("testbench", (HSimInstFactoryPtr)IF8);
        (*cfgvh).addVlogModule("glbl", (HSimInstFactoryPtr)IF9);
        HSim__s5 * topvl = 0;
        topvl = new workMcpu__tbw("cpu_tbw");
        topvl->moduleInstantiate(cfgvh);
        addChild(topvl);
        topvl = new workMglbl("glbl");
        topvl->moduleInstantiate(cfgvh);
        addChild(topvl);
        return cfgvh;
}
};

main(int argc, char **argv) {
  HSimDesign::initDesign();
  globalKernel->getOptions(argc,argv);
  HSim__s6 * _top_i = 0;
  try {
    HSimConfigDecl *cfg;
 _top_i = new _top();
  cfg =  _top_i->topModuleInstantiate();
    return globalKernel->runTcl(cfg, _top_i, "_top", argc, argv);
  }
  catch (HSimError& msg){
    try {
      globalKernel->error(msg.ErrMsg);
      return 1;
    }
    catch(...) {}
      return 1;
  }
  catch (...){
    globalKernel->fatalError();
    return 1;
  }
}
