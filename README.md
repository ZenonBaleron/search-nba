# search-nba

## overview

The content of this repository is primarily meant as a fulfillment of the Final Project requirement of the UIUC CS410 graduate class that I took in the Fall of 2017. The class was an excellent overview of Text Retrieval methods.

I have chosen to built a simple, vertical search engine. This search engine is concerned with sports, specifically with basketball, and with the NBA league coverage in particular.

[metapy], a python interface to [MeTA toolkit], is this project's central building block. The MeTA framework was born out of the UIUC CS
community, and it was part of our multiple MP assignments throughout the course.

MeTA was used on text data from publically available articles with NBA as the main topic. These articles had to be first scraped, parsed, cleaned, and converted into one of the input formats supported by the framework: file corpus with metadata.

## implementation

Details of implementation can be demonstrated by an outline of installation. To get the entire system up, one needs to combine the following three elements:
- system
- software
- data

### system provisioning

Here's a walkthrough of what it took to bring up this search engine on an AWS EC2 instance.

An AWS account was created, and an instance was launched. The size of the instance was t2.micro, the image used was ami-7707a10f, and the storage was an 8GB EBS gp2 volume. At the time of creation, the SSH key was downloaded to the local workstation to facilitate remote shell access later. The instance was configured with a public IP address.

A special Security Group was created for this instance. TCP ports 22 and 4410 were opened to allow external access to SSH and the Flask server, respectively.

The EC2 instance comes pretty bare, so we install some basic requirements:
- pip
- virtualenv
- metapy
- flask

```bash
# base of execution is /home/ec2-user
cd

# install pip
wget https://bootstrap.pypa.io/get-pip.py
sudo python get-pip.py

# install virtualenv
sudo pip install virtualenv

# install git
sudo yum install git

# pull the code from the repo
git clone https://github.com/ZenonBaleron/search-nba.git

# create a virtual environment and activate it
mkdir env
virtualenv env/search-nba
source env/search-nba/bin/activate

# install metapy and Flask
pip install metapy
pip install Flask
```

#### data preparation

Here's a walkthrough of what it took to compile the file corpus, and how to keep it up-to-date.

Any number of document sources is supported, but one source is described here: [ESPN NBA News Archive]. On this website ESPN lists archival, NBA-related articles from 2003 all the way to the present day. There is one list of links per month.

Each specific source needs a custom scraper. For this source I created a perl script that is invoked in the following way:

```bash
# base of execution is /home/ec2-user
cd

# get the list of links to December 2017 articles, and build a file corpus
search-nba/code/fetch/espn-nba-news-archive.pl --year 2017 --month 12
```

The output of this script is a valid metapy **file corpus**, consisting of one file per document and a common **metadata.dat** file.

The directory containg this corpus might be:

```bash
# note the date-time suffix indicating the time of the data scrape
search-nba/data/corpus/espn-nba-news-archive.20171218091319
```

The metadata fields are like this:
```
metadata = [
  { name = "path",     type = "string" }, # name of the file is the md5 of the original URL
  { name = "date_pub", type = "uint" },   # epoch time of when the article was published
  { name = "date_got", type = "uint" },   # epoch time of ehrn the article was scraped
  { name = "src_tag",  type = "string" }, # tag associated with the source of the article
  { name = "path",     type = "string" }  # the URL of the original article
]
```

Once several per-month corpora are pulled, they may be merged into each other. For this I also wrote a perl script. It can be invoked like so:

```bash
# merge the 'minor' corpus into the 'major' corpus
search-nba/code/merge-corpora.pl --major nba --minor espn-nba-news-archive.20171218091319
```

The above steps can be automated via cron to refresh the major corpus periodically.

I tried to get each article from the last five years. I have found that the server that ESPN uses for this archive site is not responsive a lot of times. About half of the months could not be pulled (various 5XX errors observed). For the months that were reachable, there were anywhere from 200 to 900 articles in a month, with an average around 600. Out of the 23k+ articles listed, some were dead links. About 89% of the listed articles were reachable, and that's around 20k articles. Size of this corpus is 40MB as ZIP and 120MB raw.
- Detailed counts of articles obtained can be found in this [Google spreadsheet].
- The current corpus can be obtained from S3: [Download ZIP of corpus]

Quite a bit of time was put into the examination of site HTML and formulating the LibXML parser through appropriate XPath expressions. Along the way numerous one-off cases and exceptions were identified and worked around. Typical pains of web scraping.

## usage

Corpus can be indexed and searched
- through the python command line, by leveraging metapy calls
- through the web interface, which is a front to the metapy calls

'''bash
# pull the corpus
cd /home/ec2-user/search-nba/data
bash unzip-corpus-here

# build the index
cd /home/ec2-user/search-nba/data/corpus
python query-nba "Chicago Bulls champions"
'''

Web interface should be available at the following link eventually, although to be honest I haven't had time to quite finish it yet. Assembling the corpus took most of the time alloted for this project.

http://52.24.255.21:4410/search-nba/

[MeTA toolkit]: https://meta-toolkit.org/
[metapy]: https://github.com/meta-toolkit/metapy
[Google spreadsheet]: https://goo.gl/kDG6M7
[Download ZIP of corpus]: http://cs410-search-nba.s3-website-us-west-2.amazonaws.com/corpus.zip
