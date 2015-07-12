#!/bin/sh

#proměnné
#source="/tmp/pokus/HDD1/"
#destination="/tmp/pokus/HDD2"
#md5file="/tmp/backup_check_sums.md5"
#logfile="/tmp/log/backup"
source=`uci get backup.@global[0].source`
destination=`uci get backup.@global[0].destination`
md5file=`uci get backup.@global[0].md5file`
logfile=`uci get backup.@global[0].logfile`

# skript pro synchonizaci obsahů zálohované části HDD
# HDD jsou dva a oba mají stejně velký oddíl, primární je 5 TB a jednou za čas se data nakopírují pomocí rsync na druhý 500 GB HDD
#
# synchronizace se pouštětí jen pokud se stala nějaká změna, provádíme výpočet MD5 z obsahu souborů
# kontrolní součty pro soubory budou v $logfile
# nice pro spuštění v režimu nižší priority (nejnižší 20, normální 0, nejvyšší -20)

Init()
{
	rm /etc/config/backup && touch /etc/config/backup
	uci add backup global
	uci set backup.@global[0].source=/tmp/pokus/HDD1/
	uci set backup.@global[0].destination=/tmp/pokus/HDD2
	uci set backup.@global[0].md5file=/tmp/backup_check_sums.md5
	uci set backup.@global[0].logfile=/tmp/log/backup
	uci commit && cat /etc/config/backup

}

RunBackup()
{
	nice -n 20 \
		rsync -az \
		$source/ $destination
	# ještě si to zalogujeme do syslogu
	logger "Záloha provedena"
	echo "Záloha provedena"
	datetime=`date +"%d.%m.%Y %H:%M:%S"`
	echo "$datetime	Záloha provedena" >> $logfile

	# ze zálohy provedene výpočet kontrolních součtů
	#md5sum $destination/* > $md5file
	find $destination/ -type f -print0 | xargs -0 md5sum > $md5file
	# MD5tku počítáme ze zálohy, musíme tedy pro příští kontrolu změnit cestu na originální umístění
	sed -i "s#$destination#$source#g" $md5file # místo lomítek použijeme hash aby nám nevadila substituce
}

source=${source%/}	# aby nám nevadilo zadání /xy/ab ani /xy/ab/
destination=${destination%/} 

#nejprve provedeme kontrolu kontrolních součtů abychom zkontrolovali zda je potřeba zálohovat
# a potom jednomu z té kontroli šíbne (:-)

# find vypíšeme seznam souborů a složek, každý na jeden řádek, přepínač -type vybírá jen soubory
# wc -l spočítáme počet řádků (přepínač -l)
sourcecount=`find $source -type f | wc -l`
destcount=`cat $md5file 2> /dev/null | wc -l` # 2> /dev/null přesměruje chybu, pokud soubor s MD5 součte neexistuje

if [ $sourcecount != $destcount ]; # pokud není počet souborů ve zdrojovém umístění shodný s počtem souborů v záloze, tak zálohuj
then
	RunBackup
else # počet souborů mohl zůstat stejný ale změnil se jejich obsah, zkontrolujeme tedy kontrolní součty
	md5sum -cs $md5file 2> /dev/null
	if [ "$?" != 0 ];
	then
		RunBackup
	else
		logger "Záloha provedena: záloha aktuální, nebylo co zálohovat"
		echo "Záloha provedena: záloha aktuální, nebylo co zálohovat"
	fi
fi
