configuration DataGeneratorC {
  provides interface Notify<group_project_msg_t>;
}
implementation {
  components DataGeneratorP;
  components MainC;
  components new TimerMilliC();
  components DataGeneratorRandomC;
    
  DataGeneratorP.Boot -> MainC.Boot;
  DataGeneratorP.MilliTimer -> TimerMilliC;
  DataGeneratorP.Random -> DataGeneratorRandomC;
  
  Notify = DataGeneratorP;
}