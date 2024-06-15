# Monitorless

Monitorless is a performance degradation predictor.
The implementation is based on the following paper [\[1\]](https://dl.acm.org/doi/pdf/10.1145/3361525.3361543).

## Dataset

The dataset measurements were conducted on Google Cloud Compute Engine VM instances.
The following two instance types were used:

1. Loadgeneration VM running the respective load client for the benchmark:
   - Machine type: e2-medium
   - Region: us-central1-a
   - Operating System: Ubuntu 24.04 LTS
   - Kernel: 6.8.0-1008-gcp
   - CPU: Intel Xeon (2) @ 2.200GHz
   - CPU-Platform: Intel Broadwell
   - Architecture: x86/64
   - Memory: 4GB
2. Application VM running the respective target application for the benchmark:
   - Machine type: e2-standard-8
   - Region: us-central1-a
   - Operating System: Ubuntu 24.04 LTS
   - Kernel: 6.8.0-1008-gcp
   - CPU: Intel Xeon (8) @ 2.200 GHz
   - CPU-Platform: Intel Broadwell
   - Architecture: x86/64
   - Memory: 32GB

|  #  | Service   | CPU, MEM | Par |     Traffic     |
| :-: | :-------- | :------: | :-: | :-------------: |
|  1  | Solr      |  3, 30   |  -  |     sin1000     |
|  2  | Solr      |  8, 30   |  -  |     sin1000     |
|  3  | Solr      |   8, 8   | 14  |  sinnoise1000   |
|  4  | Solr      |   8, 8   | 15  |  sinnoise1000   |
|  5  | Solr      |   3, 8   | 16  |  sinnoise1000   |
|  6  | Solr      |  1.5, 8  | 17  |  sinnoise1000   |
|  7  | Memcached |  8, 30   |  -  |   2K-50K R/s    |
|  8  | Memcached |  1, 30   |  -  |   20K-85K R/s   |
|  9  | Memcached |   8, 8   |  -  |   39K-45K R/s   |
| 10  | Memcached |   8, 4   | 18  |   10K-65K R/s   |
| 11  | Cassandra |  8, 28   |  -  | A: 30K-100K R/s |
| 12  | Cassandra |  8, 28   |  -  | B: 20K-70K R/s  |
| 13  | Cassandra |  8, 28   |  -  | D: 40K-90K R/s  |
| 14  | Cassandra |  6, 28   |  3  | A: 15K-25K R/s  |
| 15  | Cassandra |  6, 28   |  4  | B: 10K-15K R/s  |
| 16  | Cassandra |  6, 28   |  5  | D: 10K-25K R/s  |
| 17  | Cassandra |  6, 28   |  6  |  B: 5K-20K R/s  |
| 18  | Cassandra |  6, 28   | 10  |   B: 10K R/s    |
| 19  | Cassandra |  1, 28   |  -  |   F: 200 R/s    |
| 20  | Cassandra |  1, 28   |  -  |    F: 20 R/s    |
