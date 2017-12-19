# search-nba

## overview

The content of this repository is primarily meant as a fulfillment of the Final Project requirement of the UIUC CS410 graduate class that I took in the Fall of 2017. The class was an excellent overview of Text Retrieval methods.

I have chosen to built a simple, vertical search engine. This search engine is concerned with sports, specifically with basketball, and with the NBA league coverage in particular.

## implementation

[metapy], a python interface to [MeTA toolkit], is this project's central building block. The MeTA framework was born out of the UIUC CS
community, and it was part of our multiple MP assignments throughout the course.

MeTA was used text data from publically available articles on NBA. These articles had to be first scraped, parsed, cleaned, and converted into one of the input formats supported by the framework: file corpus with metadata.

## usage

[MeTA toolkit]: https://meta-toolkit.org/
[metapy]: https://github.com/meta-toolkit/metapy
