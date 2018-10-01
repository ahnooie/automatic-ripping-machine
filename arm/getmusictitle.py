#!/usr/bin/python3
from discid import read
import logging
import musicbrainzngs as mb
from subprocess import run, PIPE

from classes import Disc

def main(disc):
	"""
	Depending on the configuration musicbrainz or freedb is used
	to identify the music disc. The label of the disc is returned
	or "".
	"""
	from config import cfg
	discid = get_discid(disc)
	if cfg['GET_AUDIO_TITLE'] == 'musicbrainz':
		return musicbrainz(discid)
	elif cfg['GET_AUDIO_TITLE'] == 'freecddb':
		return cddb(discid)
	elif cfg['GET_AUDIO_TITLE']  == 'none':
		return ""
	else:
		return ""
    	
def get_discid(disc):
	"""
	Calculates the identifier of the disc
	
	return:
	identification object from discid package
	"""
	return read(disc.devpath)

def musicbrainz(discid):
	"""
	Ask musicbrainz.org for the release of the disc
	
	arguments:
	discid - identification object from discid package
	
	return:
	the label of the disc as a string or "" if nothing was found 
	"""
	mb.set_useragent("arm","v1.0")
	try:
		infos = mb.get_releases_by_discid(myid)
		logging.debug("Infos: %s", infos)
		return infos['disc']['release-list'][0]['title']
	except mb.WebServiceError as exc:
		if exc.cause.code == 404:
			return ""
		else:
			logging.error("%s", exc)

def cddb(discid):
	"""
	Ask freedb.org for the label of the disc and uses the command line tool
	cddb-tool from abcde
	
	arguments:
	discid - identification object from discid package
	
	return:
	the label of the disc as a string or "" if nothing was found 
	"""
	cddburl = "http://freedb.freedb.org/~cddb/cddb.cgi"
	command = ['cddb-tool', 'query', cddburl,'6', 'arm', 'armhost', discid.freedb_id, str(len(discid.tracks))]
	command += [str(track.offset) for track in discid.tracks]
	command += [str(discid.seconds)]
	logging.debug("command: %s", " ".join(command))
	ret = run(command, stdout=PIPE, universal_newlines=True)
	if ret.returncode == 0:
		infos = [line for line in ret.stdout.split("\n")]
		logging.debug("Infos: %s",infos)
		firstline = infos[0].split(" ")
		status = int(firstline[0])
		logging.debug("status: %d, firstline: %s", status, firstline)
		if status == 200: # excat match
			title = " ".join(firstline[3:])
		elif status == 210 or status == 211: # multiple
			infos = infos[-3] # last entry
			title = " ".join(infos.split(" ")[2:])
		else: # nothing found
			title = ""
		return title
	else:
		return ""
	

if __name__ == "__main__":
	# test code
	logging.basicConfig(level=logging.DEBUG)
	disc = Disc("/dev/cdrom")
	myid = get_discid(disc)
	logging.info("DiscID: %s (%s)", str(myid), myid.freedb_id)
	logging.info("URL: %s", myid.submission_url)
	logging.info("Tracks: %s", myid.tracks)
	logging.info("Musicbrain: %s", musicbrainz(myid))
	
	logging.info("freedb: %s", cddb(myid))
    
