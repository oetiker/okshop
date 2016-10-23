OkShop
======
Version: 0.1.0
Date: 2016-10-05

The shop software used to sell the Oltner-Kalender.

SETUP
-----

  ./configure
  make
  make install


RUNNING
-------

Run okshop like this:

   bin/okshop.pl daemon --listen 'http://okshop:3834'

To run behind a reverse proxy, add the --proxy option

   bin/okshop.pl daemon --proxy --mode=production --listen 'http://okshop:3834'



Enjoy!

Tobias Oetiker <tobi@oetiker.ch>
