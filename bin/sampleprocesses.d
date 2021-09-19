#!/usr/sbin/dtrace -s

#pragma D option quiet
#pragma D option aggsortkey

BEGIN
{
    printf("Tracing for %s (sampling every %s)...\n", $$2, $$1);
}

profile-$$1
{
    this->name = curthread->last_processor->state == 4 ? "idle" : execname;
    @timebycpu[cpu, this->name] = count();
    @total[this->name] = count();
}

tick-$$2
{
    printf("CPU\t%30s\t%5s\n", "Process", "Count");
    printa("%3d\t%30s\t%@5d\n", @timebycpu);
    
    printf("\n");
    
    printf("   \t%30s\t%5s\n", "Process", "Count");
    printa("   \t%30s\t%@5d\n", @total);
    
    exit(0);
}
