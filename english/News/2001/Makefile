# If this makefile is not generic enough to support a translation,
# please contact debian-www.

WMLBASE=../..
CUR_DIR=News/2001
SUBS=

GETTEXTFILES += newsevents.mo

NOGENERICDEP := true
include $(WMLBASE)/Make.lang

%.$(LANGUAGE).html: %.wml $(TEMPLDIR)/news.wml $(GETTEXTDEP)
	$(WML) $(<F)
index.$(LANGUAGE).html: index.wml $(TEMPLDIR)/template.wml \
  $(TEMPLDIR)/recent_list.wml $(wildcard 2001*.wml) \
  $(wildcard $(ENGLISHDIR)/News/2001/2001*.wml) $(GETTEXTDEP)
