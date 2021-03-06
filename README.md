# QueryStoreReplay
[![licence badge]][licence]
[![stars badge]][stars]
[![forks badge]][forks]
[![issues badge]][issues]

[licence badge]:https://img.shields.io/badge/license-MIT-blue.svg
[stars badge]:https://img.shields.io/github/stars/Evdlaar/QueryStoreReplay.svg
[forks badge]:https://img.shields.io/github/forks/Evdlaar/QueryStoreReplay.svg
[issues badge]:https://img.shields.io/github/issues/Evdlaar/QueryStoreReplay.svg

[licence]:https://github.com/Evdlaar/QueryStoreReplay/blob/master/LICENSE
[stars]:https://github.com/Evdlaar/QueryStoreReplay/stargazers
[forks]:https://github.com/Evdlaar/QueryStoreReplay/network
[issues]:https://github.com/Evdlaar/QueryStoreReplay/issues

Query Store Replay is a Powershell script that allows you to replay query workload directly from a Query Store enabled database to either the same database or a database on another machine.

## Prerequisites
- Microsoft SQL Server 2016 or higher
- Query Store feature enabled on the source database
- SQL Server Management Objects (SMO) installed on the machine that will run the Query Store Replay script

## Start using the Query Store Replay script
All the information you need to start using the Query Store Replay script can be found on the wiki: https://github.com/Evdlaar/QueryStoreReplay/wiki.

## Additional information
The Query Store Replay script is developed and maintained by Enrico van de Laar (Twitter: @evdlaar).
If you run into any issues or bugs when using this script please let me know!

Special thanks goes to Rob Sewell (@sqldbawithbeard) for helping me out with Powershell!

## License
[MIT](/license.md)