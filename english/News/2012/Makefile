# If this makefile is not generic enough to support a translation,
# please contact debian-www.

WMLBASE=../..
CUR_DIR=News/2012
SUBS=

GETTEXTFILES += newsevents.mo

NOGENERICDEP := true
include $(WMLBASE)/Make.lang

%.$(LANGUAGE).html: %.wml $(TEMPLDIR)/news.wml $(GETTEXTDEP)
	$(WML) $(<F)
index.$(LANGUAGE).html: index.wml $(TEMPLDIR)/template.wml \
  $(TEMPLDIR)/recent_list.wml $(wildcard 2012*.wml) \
  $(wildcard $(ENGLISHDIR)/News/2012/2012*.wml) $(GETTEXTDEP)

