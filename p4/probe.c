// Independent userspace walk: read every 64-bit entry from /dev/dram.
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/utsname.h>

typedef unsigned long long U;
struct item { char key[64], val[256]; } cfg[64];
static int nc;
static const char *names[] = {"pgd", "pud", "pmd", "pte"};
static const unsigned shifts[] = {39, 30, 21, 12};
struct step { U table, index, slot, raw, base; };
struct walk { struct step s[4]; U va, pa, offset; int leaf; };
static void die(const char *s) { perror(s); exit(1); }
static void require(int ok, const char *s)
{ if (!ok) { fprintf(stderr, "P4_VERIFY_FAIL: %s\n", s); exit(1); } }
static const char *str(const char *key)
{
    int i;
    for (i=0; i<nc; ++i) if (!strcmp(cfg[i].key,key)) return cfg[i].val;
    fprintf(stderr,"Missing configuration: %s\n",key); exit(1);
}
static U get(const char *key) { return strtoull(str(key),NULL,0); }
static void read_cfg(void)
{
    FILE *f=fopen("/proc/p4_walk","r"); char line[384];
    if (!f) die("/proc/p4_walk");
    while (fgets(line,sizeof(line),f)) {
        char *p=strchr(line,'=');
        if (!p || nc==64) continue;
        *p++=0; p[strcspn(p,"\r\n")]=0;
        snprintf(cfg[nc].key,sizeof(cfg[nc].key),"%s",line);
        snprintf(cfg[nc++].val,sizeof(cfg[0].val),"%s",p);
    }
    fclose(f);
}
static void read_ram(int fd, U addr, void *buf, size_t n)
{
    size_t done=0;
    while(done<n) {
        ssize_t r=pread(fd,(char*)buf+done,n-done,(off_t)(addr+done));
        if(r<0 && errno==EINTR) continue;
        if(r<=0) die("pread /dev/dram");
        done+=(size_t)r;
    }
}
static struct walk translate(int fd, U va)
{
    struct walk w={0}; U table=get("root"), mask=get("mask"); int i;
    w.va=va;
    for(i=0;i<4;i++) {
        struct step *s=&w.s[i];
        s->table=table; s->index=(va>>shifts[i])&511;
        s->slot=table+s->index*8;
        read_ram(fd,s->slot,&s->raw,8);
        require((s->raw&1)!=0,"entry must be present");
        s->base=s->raw&mask;
        if(i==3 || ((i==1 || i==2) && (s->raw&128))) {
            U offmask=(1ULL<<shifts[i])-1;
            s->base &= ~offmask;
            w.offset=va&offmask; w.pa=s->base+w.offset; w.leaf=i;
            return w;
        }
        table=s->base;
    }
    require(0,"no leaf"); return w;
}
static void flagline(U raw, int leaf)
{
    printf("flags: P=%llu RW=%llu US=%llu A=%llu D=%llu G=%llu NX=%llu\n",
      raw&1,(raw>>1)&1,(raw>>2)&1,(raw>>5)&1,(raw>>6)&1,(raw>>8)&1,(raw>>63)&1);
    printf("bit 7: %s=%llu\n",leaf ? "PAT (4KB leaf)" : "PS (directory)",(raw>>7)&1);
}
static void stage(int fd, const char *name)
{
    struct walk w=translate(fd,get("vaddr"));
    int i, folded=!strcmp(name,"p4d"); char key[64];
    require(w.leaf==3,"4KB alias must reach PTE");
    for(i=0;i<4;i++) if(!strcmp(names[i],name)) break;
    if(folded) i=0;
    require(i<4,"known page-table level");
    struct step *s=&w.s[i];
    snprintf(key,sizeof(key),"%s_slot",name);
    require(s->slot==get(key),"slot matches kernel helper walk");
    snprintf(key,sizeof(key),"%s_raw",name);
    require(((s->raw^get(key))&~(32ULL|64ULL))==0,"RAM value matches module (A/D may change)");
    printf("v_addr = 0x%016llx   root = 0x%016llx\n",w.va,get("root"));
    if(folded) {
        puts("Linux P4D is FOLDED: PTRS_PER_P4D=1, p4d_index=0.");
        puts("p4d_offset(pgd, va) reuses the PGD entry; no extra RAM table read.");
        printf("P4D entry address = PGD entry address = 0x%016llx\n",s->slot);
        printf("P4D value = PGD value = 0x%016llx\n",s->raw);
        puts("Hardware: PGD -> PUD -> PMD -> PTE (four levels).");
    } else {
        printf("%s index = (v_addr >> %u) & 0x1ff = %llu (0x%03llx)\n",name,shifts[i],s->index,s->index);
        printf("Table base (physical) = 0x%016llx\n",s->table);
        printf("Entry address = table + index * 8\n");
        printf("              = 0x%016llx + 0x%llx = 0x%016llx\n",s->table,s->index*8,s->slot);
        printf("pread(/dev/dram, entry address, 8) = 0x%016llx\n",s->raw);
        flagline(s->raw,i==3);
    }
    printf("Physical address mask = 0x%016llx\n",get("mask"));
    printf("Entry & mask = 0x%016llx\n",s->base);
    if(i==3) puts("PTE points to the DATA page frame. Add the 12-bit page offset next.");
    else puts("This value points to the NEXT table, not to the string data.");
    puts("PASS: independent physical RAM read agrees with kernel page-table helpers.");
    fflush(stdout);
}
int main(int argc,char **argv)
{
    int fd; struct walk w;
    require(argc>=2,"mode required"); read_cfg();
    if(!strcmp(argv[1],"value")) {
        require(argc==3,"value key required"); printf("%s\n",str(argv[2])); return 0;
    }
    fd=open("/dev/dram",O_RDONLY); if(fd<0) die("open /dev/dram");
    w=translate(fd,get("vaddr"));
    require(w.pa==get("paddr") && w.pa==get("expected"),"independent final PA matches virt_to_phys");
    if(!strcmp(argv[1],"setup")) {
        struct utsname u; uname(&u);
        printf("Running guest: %s %s %s\n",u.sysname,u.release,u.machine);
        puts("Original example: __get_free_page(), write message, free_page() at unload.");
        puts("Extension: vmap() the SAME page to guarantee a complete 4KB PTE path.");
        printf("Direct-map base = 0x%016llx\n",get("direct_base"));
        printf("4KB alias base  = 0x%016llx\n",get("alias_base"));
        printf("Test v_addr     = 0x%016llx (alias + 0x123)\n",get("vaddr"));
        printf("CR0 = 0x%016llx (PG=%llu), CR3 = 0x%016llx\n",get("cr0"),(get("cr0")>>31)&1,get("cr3"));
        printf("CR3 & physical-page mask = root PGD PA 0x%016llx\n",get("root"));
        puts("Level       PGD  P4D  PUD  PMD  PTE  offset");
        printf("Shift       %3llu  %3llu  %3llu  %3llu  %3llu    0\n",get("pgdir_shift"),get("p4d_shift"),get("pud_shift"),get("pmd_shift"),get("page_shift"));
        printf("Entries     %3llu  %3llu  %3llu  %3llu  %3llu\n",get("pgd_entries"),get("p4d_entries"),get("pud_entries"),get("pmd_entries"),get("pte_entries"));
        printf("Indices     %3llu    0  %3llu  %3llu  %3llu   0x%03llx\n",w.s[0].index,w.s[1].index,w.s[2].index,w.s[3].index,w.offset);
        puts("P4D is folded; four hardware levels, 512 entries/table, 8 bytes/entry.");
        puts("Data written by the kernel module:"); printf("\"%s\"\n",str("message"));
        puts("PASS: module and independent /dev/dram walker agree on final PA.");
    } else if(!strcmp(argv[1],"data")) {
        char buf[128]={0}; U len=strlen(str("message"))+1;
        read_ram(fd,w.pa,buf,(size_t)len);
        require(!strcmp(buf,str("message")),"physical data matches kernel message");
        printf("v_addr       = 0x%016llx\n",w.va);
        printf("PTE raw      = 0x%016llx\n",w.s[3].raw);
        printf("Frame base   = PTE & 0x%016llx = 0x%016llx\n",get("mask"),w.s[3].base);
        printf("Page offset  = v_addr & 0xfff = 0x%03llx\n",w.offset);
        printf("p_addr       = frame + offset = 0x%016llx\n",w.pa);
        printf("virt_to_phys(original + offset) = 0x%016llx\n",get("expected"));
        printf("pread(/dev/dram, p_addr, %llu):\n\"%s\"\n",len,buf);
        puts("PASS: page-table calculation, kernel reference, and actual RAM bytes match.");
        puts("Use entry flags to check permissions; strip flags/NX before using an address.");
        puts("x86 stores each 64-bit entry little-endian; Q view decodes the whole value.");
    } else if(!strcmp(argv[1],"data")) {
        char buf[128]={0};
        require(w.leaf==3,"PTE leaf");
        printf("v_addr = 0x%016llx\n",w.va);
        printf("Indices: PGD=%llu PUD=%llu PMD=%llu PTE=%llu\n",w.s[0].index,w.s[1].index,w.s[2].index,w.s[3].index);
        printf("PTE raw = 0x%016llx\n",w.s[3].raw);
        printf("Frame = PTE & 0x%016llx = 0x%016llx\n",get("mask"),w.s[3].base);
        printf("Offset = v_addr & 0xfff = 0x%03llx\n",w.offset);
        printf("p_addr = frame + offset = 0x%016llx + 0x%03llx\n",w.s[3].base,w.offset);
        printf("       = 0x%016llx\n",w.pa);
        printf("Kernel helper walk = 0x%016llx\n",get("paddr"));
        printf("virt_to_phys(original + offset) = 0x%016llx\n",get("expected"));
        read_ram(fd,w.pa,buf,strlen(str("message"))+1);
        require(!strcmp(buf,str("message")),"real physical bytes match written string");
        printf("Physical RAM string = \"%s\"\n",buf);
        puts("PASS: independent walk, kernel walk, virt_to_phys and actual bytes all agree.");
        puts("The 0x123 offset is preserved; flags are excluded from the physical address.");
    } else if(!strcmp(argv[1],"direct")) {
        struct walk d=translate(fd,get("direct_va")); char a[128]={0},b[128]={0}; int i;
        require(d.pa==w.pa,"both VAs map same physical byte");
        printf("Original direct-map v_addr = 0x%016llx\n",d.va);
        for(i=0;i<=d.leaf;i++) printf("%s: index=%3llu slot=0x%llx raw=0x%016llx\n",names[i],d.s[i].index,d.s[i].slot,d.s[i].raw);
        printf("Actual leaf: %s, mapping size=0x%llx bytes\n",names[d.leaf],1ULL<<shifts[d.leaf]);
        if(d.leaf<3) puts("PS=1 at this directory: stop here; there is no PTE table for this mapping.");
        printf("Direct-map PA = frame 0x%llx + offset 0x%llx = 0x%llx\n",d.s[d.leaf].base,d.offset,d.pa);
        printf("4KB alias PA  = frame 0x%llx + offset 0x%llx = 0x%llx\n",w.s[3].base,w.offset,w.pa);
        read_ram(fd,d.pa,a,strlen(str("message"))+1); read_ram(fd,w.pa,b,strlen(str("message"))+1);
        require(!strcmp(a,b) && !strcmp(a,str("message")),"alias data identity");
        printf("Both physical reads: \"%s\"\n",a);
        puts("PASS: different virtual mappings, same physical memory and identical data.");
    } else stage(fd,argv[1]);
    close(fd); return 0;
}
