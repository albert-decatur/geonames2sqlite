#/bin/bash

# put geonames into a sqlite db
# user args: 1) directory containing the following geonames txt dump files and nothing else:
#  1. allCountries.txt
#  2. admin1CodesASCII.txt
#  3. admin2Codes.txt
#  4. featureCodes_en.txt
#  5. hierarchy.txt
#
# NB: output sqlite db will be overwritten
# TODO: do not complain if table does not contain geonameid field to build index on
# example use: $0 input/ output/geonames_$(date +%F).sqlite

indir=$1
db=$2
rm $db 2>/dev/null
tmp=$(mktemp)

basenames=$(
	find $indir -type f |\
	while read name
	do
		basename $name .txt
	done
)

# split geonames TSV fields on period
# eg AF.01.1125426 becomes three fields: adm0_code, adm1_code, and adm2_code
# NB: this function relies exactly on the nature of the geonames txt files
# consulte the geonames README as needed
function fieldsplit
{
	cat $indir/featureCodes_en.txt |\
	# null is not literal string - the txt file means to refer to a null value
	grep -vE "^\bnull\b" |\
	mawk -F'\t' '{OFS="\t";gsub(/[.]/,"\t",$1);print $0}' |\
	sponge $indir/featureCodes_en.txt

	for txt in admin1CodesASCII.txt admin2Codes.txt
	do
		cat $indir/$txt |\
		mawk -F'\t' '{OFS="\t";gsub(/[.]/,"\t",$1);print $0}' |\
		sponge $indir/$txt
	done
}

# create table in sqlite db for each of the input geonames txt dump files
# NB: this function relies exactly on the nature of the geonames txt files
# consulte the geonames README as needed
function createtables
{
	cat > $tmp <<EOF
	-- allCountries ought to be broken into more tables for admin codes and feature classes
	-- otherwise we can't use admin1codesascii.adm1_code as a foreign key, or admin2codes.adm2_code, or featurecodes_en.class, or featurecodes_en.code, or 
	--PRAGMA foreign_keys = on;
	CREATE TABLE allCountries (
		geonameid INTEGER NOT NULL PRIMARY KEY,
		name TEXT,
		asciiname TEXT,
		alternatenames TEXT,
		latitude REAL,
		longitude REAL,
		featureclass TEXT,
		featurecode TEXT, 
		countrycode TIME, 
		cc2 TEXT, 
		admin1code TEXT, 
		admin2code TEXT, 
		admin3code TEXT, 
		admin4code TEXT, 
		population INTEGER, 
		elevation TEXT, 
		dem INTEGER, 
		timezone TEXT, 
		modificationdate DATE
	);
	CREATE TABLE admin1codesascii (
		adm0_code TEXT,
		adm1_code TEXT,
		adm1_name TEXT,
		adm1_asciiname TEXT,
		geonameid INTEGER NOT NULL,
		FOREIGN KEY(geonameid) REFERENCES allCountries(geonameid)
	);
	CREATE TABLE admin2codes (
		adm0_code TEXT,
		adm1_code TEXT,
		adm2_code TEXT,
		adm2_name TEXT,
		adm2_asciiname TEXT,
		geonameid INTEGER NOT NULL,
		FOREIGN KEY(geonameid) REFERENCES allCountries(geonameid)
	);
	CREATE TABLE featurecodes_en (
		class TEXT,
		code TEXT,
		name TEXT,
		description TEXT
	);
	CREATE TABLE hierarchy (
		parent_id INTEGER NOT NULL,
		child_id INTEGER NOT NULL,
		type TEXT,
		FOREIGN KEY(parent_id) REFERENCES allCountries(geonameid)
		FOREIGN KEY(child_id) REFERENCES allCountries(geonameid)
	);
EOF
	# would have used 'cat | sqlite3 $db' but hangs
	cat $tmp | sqlite3 $db
}

function copytables
{
# import each of these geonames TSVs
for table in $basenames
do
	cat > $tmp <<EOF
.separator '	'
.import $indir/${table}.txt $table
CREATE INDEX geo_${table} ON $table (geonameid);
EOF
	# would have used 'cat | sqlite3 $db' but hangs
	cat $tmp | sqlite3 $db
done
}

fieldsplit
createtables
copytables
