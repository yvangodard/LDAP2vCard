LDAP2vCard
============

Présentation
------------

Cet outil est destiné à assurer un export au format vCard des informations/coordonnées d'utilisateurs enregistrés sur un serveur LDAP.
Cet outil peut être utilisé en exportant la totalité des utilisateurs enregistrés dans le LDAP, ou en limitant l'export à certains groupes, qu'il s'agisse de groupes de type *groupOfNames* ou *posixGroup*.

Les données disponibles pour vos utilisateurs dépendent des attributs disponibles dans le schema LDAP que vous utilisez. Ici le script exploite les attributs disponibles sur un OpenDirectory (Apple Mac OS X Server 10.6).

Pour une aide complète, installer le script et lancez le :

    ./ldap2vcard.sh help


Bug report
-------------

Si vous voulez me faire remonter un bug : [ouvrir un bug](https://github.com/ygodard/ldap2vcard/issues).


Installation
---------

Pour installer cet outil, téléchargez le script dans le dossier où vous voulez l'installer :

	wget --no-check-certificate https://raw.github.com/yvangodard/ldap2vcard/master/ldap2vcard.sh ; 
	sudo chmod 755 ldap2vcard.sh


License
-------

Ce script ldap2vcard.sh de [Yvan GODARD](http://www.yvangodard.me) est mis à disposition selon les termes de la licence Creative Commons 4.0 BY NC SA (Attribution - Pas d’Utilisation Commerciale - Partage dans les Mêmes Conditions).

<a rel="license" href="http://creativecommons.org/licenses/by-nc-sa/4.0"><img alt="Licence Creative Commons" style="border-width:0" src="http://i.creativecommons.org/l/by-nc-sa/4.0/88x31.png" /></a>


Limitations
-----------

THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE REGENTS AND CONTRIBUTORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.