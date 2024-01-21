---
title: "Apple Silicon上でLima+Ubuntu(x86_64)VMのメモ"
emoji: "🍎"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["Mac", "Lima"]
published: true
---

Apple Silicon搭載のMac上でx86（x86_64含む）用のバイナリやコンテナイメージ等を実行したいことがときどきあります。
Intel Mac時代ではLinux環境での再現を行いたい場合にはそのままDocker Desktopで事足りてて、VMが必要ならVirtualBox+[Vagrant](https://www.vagrantup.com/)を使っていました。
Apple Silicon環境むけには現時点ですでにいくつかの代替手段があるようです。

* [UTM](https://mac.getutm.app/)でQEMUでx86エミュレートされた仮想環境を実行
  * 現状CLIで操作できない
* [multipass](https://multipass.run/)での仮想環境内でlibvirtをproviderとしてx86エミュレートされたVMをVagrantで実行
  * CLI化は可能ながらVMの中にVMを立てるような少しアクロバティックな構成になりそれだけ操作も煩雑
  * ネットワーク周りが難しいようでゲスト内に入ることができないなど実用上難易度が高かった
* [Lima](https://github.com/lima-vm/lima)を使いQEMUでx86エミュレートされた仮想環境を実行
  * CLIで操作可能
* ...

開発用途に使うにあたっては現時点ではLimaを使うのが最も体験がよさそうです。
基本的には公式資料に必要な情報は揃っているのですが、試すにあたって必要な範囲の情報をメモがてらにまとめたり、自分の使い方に合わせてのカスタマイズをメモしています。


# Limaを使ってApple SiliconのMac上にx86 emulated Ubuntu VMを立てる手順全体感

* [Limaを導入](https://lima-vm.io/docs/installation/)する
  * `.zshrc` に `eval "$(limactl completion zsh)"` を追記するとシェル補完が効くのでおすすめ（必須）。bashにも対応しています。
* [Configuration guide](https://lima-vm.io/docs/config/)や[サンプル](https://github.com/lima-vm/lima/blob/master/examples/README.md)や参考に、config yamlを用意・記述する
* [`limactl`](https://lima-vm.io/docs/usage/) コマンドでVMを作成・起動・確認・停止・削除する
* 使い方
  * VM内で動かしたDockerコンテナをホストから直接操作
  * VMにshellで入って任意の操作

どのように使うかによってconfigをどのように作成・管理するかが変わってくるかなと思います。


# VM内でdockerコンテナを実行する方法

Limaで立てたx86 emulatedなUbuntu VMの中で、x86向けにビルドされた任意のdockerコンテナを実行することができます。VM内で動くdockerdに接続可能なソケットがホストへ露出されており、**MacOSホスト上のdockerコマンドの操作でゲスト内のx86 Ubuntu環境で動くdockerコンテナの操作ができます**。

例えば今扱っているプロジェクトでDockerfileがすでに存在しておりそれがx86を想定している場合などでは、ホスト上でのdockerコマンドの直接操作で完結するため最も体験が良いでしょう（ホストがx86環境の場合と同一の体験を実現できる）。

このような用途のためのconfiguration yamlが[サンプルとして提供されています](https://github.com/lima-vm/lima/blob/master/examples/docker.yaml)。このconfig自体はCPUアーキテクチャ（x86/aarch64）に応じて適切な方のVMイメージを展開する設定となっていますが、今回はx86 emulated VMが欲しいため **冒頭にアーキテクチャ指定を含める必要があります**。

```yaml
arch: "x86_64"       # ここを追記
images:
# Try to use release-yyyyMMdd image if available. Note that release-yyyyMMdd will be removed after several months.
- location: "https://cloud-images.ubuntu.com/releases/22.04/release-20231211/ubuntu-22.04-server-cloudimg-amd64.img"
  arch: "x86_64"
...
```


configuration yamlファイルを `limactl` に渡すと、（デフォルトでは）そのyamlファイル名をもとにVM名が決定されます。

```bash
$ limactl start --tty=false docker.yml
...
...
INFO[0318] Message from the instance "docker":
To run `docker` on the host (assumes docker-cli is installed), run the following commands:
------
docker context create lima-docker --docker "host=unix:///Users/xxxxx/.lima/docker/sock/docker.sock"
docker context use lima-docker
docker run hello-world
------
```

数分後、VM作成が成功すると最後に、ホストOS上のdockerコマンドからゲストOS内のdockerdを操作する設定が提示されます。コンテキスト名は好きなように変えてOK。この操作はVMを立てるごとに1回実施すればOK。


```bash
$ docker context create lima-docker --docker "host=unix:///Users/xxxxx/.lima/docker/sock/docker.sock"
Successfully created context "lima-docker"

$ docker context use lima-docker
Current context is now "lima-docker"
```

テストとして、Ubuntuのコンテナ内でのCPUアーキテクチャを確認してみましょう。確かにコンテナはx86で動いていることが確認できます。

```bash
% docker run ubuntu:22.04 /bin/bash -c "uname -m"
x86_64
```

この要領で、既存のDockerfileに対しても `docker build` からの `docker run` で動作確認したりデバッグしたりといったことが可能です。


config yamlをどのような単位で作成しどのように管理するか──つまり、Lima VMを必要とするプロジェクトごとに作るべきか・PC全体で1個作ったVMを使い回すか、またその中間的な管理をするかは問題になるかと思います。
ここで紹介したdockerベースの使い方の場合、同じPC上で並行作業する別のプロジェクトがありそれぞれがx86 emulatedな環境が必要な場合でも、PC内に1つyamlを用意しておきそれを使い回す選択肢も可能です。
もちろんプロジェクト単位でも構わないです（チームメンバーの他のM1/M2 Mac使いのために再現方法をプロジェクトに含めることは大きな意義がある）。


## 自動起動

ここまでの方法によってVMの存在を意識することない体験を実現できますが、その分VMを立て忘れてホスト上のdocker contextが壊れた状態で混乱することもありそうです。

PCを起動した際にVMが自動で立ち上がるよう設定すると立て忘れは減らせるでしょう。VMが常に動くことになるのでバッテリとの相談ではあります。

以下のような雑なシェルスクリプトを記述します。
これは実行された際にVMを起動し、docker contextを更新します（これは内容を変えるわけじゃないので必要ではない気もする）。
成功時・失敗時それぞれにデスクトップ通知を送ってくれるようにもしています。


```bash:/path/to/launch_docker_vm.sh
#!/bin/sh
set -eux -o pipefail

VM_NAME=docker-vm
CONTEXT_NAME=lima-${VM_NAME}

function on_error() {
  osascript -e "display notification \"${VM_NAME} start error\""
}

trap on_error ERR

export PATH=$PATH:/opt/homebrew/bin/:/usr/local/bin/
limactl start $VM_NAME
docker context update
  --docker "host=unix://$HOME/.lima/$VM_NAME/sock/docker.sock"

osascript -e "display notification \"${VM_NAME} started\""
```

このシェルスクリプトにはu+xのパーミッションを与えるようにしてください。

これをMacの起動時にユーザ権限で自動実行する設定を行います。
参考: https://www.karltarvas.com/macos-run-script-on-startup.html

```xml:~/Library/LaunchAgents/docker-vm.startup.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>docker-vm.startup</string>

    <key>OnDemand</key>
    <false/>

    <key>LaunchOnlyOnce</key>
    <true/>

    <key>UserName</key>
    <string>belltailjp</string>

    <key>ProgramArguments</key>
    <array>
        <string>/path/to/launch_docker_vm.sh</string>
    </array>
</dict>
</plist>
```

これで、Macを再起動した際に自動でVMが実行されます。
正しいdocker contextが選択されていれば、そのままホストOS上でのdockerコマンドの操作でx86エミュレーションの有効なdockerコンテナを実行できてとても便利。

```bash
$ docker run ubuntu:22.04 uname -m
x86_64
```


# VM内で直接作業する方法

多くの用途では上述の方法で十分かなと思います。しかしながら時折、Dockerコンテナではなく直接Linux環境のVMに入って作業したいこともあるかもしれません。

自分の場合、Github Actionsのワークフローをローカル実行する[act](https://github.com/nektos/act)をMacOSホスト上で動かす際、actが上記の方法で立てたdockerを使うよう[指定する](https://github.com/nektos/act#docker-context-support)……という方法がうまく動作しませんでした。
act自身をLima VM上のdockerコンテナ内で実行するのは（act自身もコンテナを作成するため）難易度が高いため、ここはしかたなく、VM内にshellで入ってそこでactを動かすことにします。

* Limaでx86 emulatedeなUbuntu VMを立てる
* VMに必要な設定をconfig yamlに記述
  * 必要な依存関係をプロビジョニング
  * ホストOSの作業ディレクトリをVM内にマウント
* VM内に入ってactコマンドを実行


## configurationについて

自前でVMの設定を記述する場合のために[configuration yamlの詳細な説明](https://github.com/lima-vm/lima/blob/master/examples/default.yaml)が提供されています。

ベースとしてはact自身dockerが必要なため先の例でも使ったDockerコンテナ実行専用のVMをもとにしつつ、以下のように変更しています。
* `act` コマンドをプロビジョニングの段階で導入（[こちら](https://github.com/nektos/act#bash-script)をプロビジョニング時に実行）
* プロジェクトのワークツリー（作業ディレクトリ）をVM内にマウント
* yamlをスリム化
* ついでにCPUとメモリも必要量を削減した設定にする


```yaml:/path/to/project/workdir/ubuntu-vm.yml
arch: "x86_64"   # <--- 追加
cpus: 1   # <--- 追加
memory: "1GiB"   # <--- 追加
disk: "6GiB"   # <--- 追加
images:
- location: "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  arch: "x86_64"
containerd:
  system: false
  user: false
provision:
- mode: system
  script: |
    #!/bin/bash
    set -eux -o pipefail
    command -v docker >/dev/null 2>&1 && exit 0
    export DEBIAN_FRONTEND=noninteractive
    curl -fsSL https://get.docker.com | sh
    # NOTE: you may remove the lines below, if you prefer to use rootful docker, not rootless
    systemctl disable --now docker
    apt-get install -y uidmap dbus-user-session
    curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | bash   # <--- 追加
    usermod -aG docker $LIMA_CIDATA_USER   # <--- 追加
- mode: user
  script: |
    #!/bin/bash
    set -eux -o pipefail
    systemctl --user start dbus
    dockerd-rootless-setuptool.sh install
    docker context use rootless

mounts:
- location: /path/to/project/workdir
  writable: true
```

yamlをどのような単位で作成・管理するか話としては、この方法ではVMをプロジェクトの必要性に合わせてプロビジョンする必要があるため、プロジェクトごとにこのyamlを作る（≒プロジェクトごとにVMを立てる）のがよいでしょう。


## VMの作成

先ほど同様にVMを作成します。
注意点として、actの場合VM内で動作させるためにユーザをdockerグループに追加する必要があり、それが反映されるにはOSを再起動する必要があったため、作成直後のVMを一旦止めて再スタートする手順をワークアラウンドとして挟んでいます。VM作成後の初回のみ必要です。
（この問題の別のワークアラウンドとしては `/var/run/docker.sock` に対して `o+rw` パーミッションを付与することですが通常好ましくない操作なのでVM再起動することにします。）

```bash
$ limactl start --tty=false ubuntu-vm.yml
$ limactl stop ubuntu-vm
$ limactl start ubuntu-vm
```

プロビジョニングのログについてはlimactlの出力には現れません。[FAQにある通り](https://lima-vm.io/docs/faq/#hints-for-debugging-other-problems)ですが、ログはログファイルに出力されています。

```bash
$ tail -f ~/.lima/ubuntu-vm/serial.log
```

## VMに入って作業

VMに入るには、limactlコマンドを使う方法と、

```bash
$ limactl shell ubuntu-vm
(ubuntu-vm)$ cd /path/to/project/dir/
(ubuntu-vm)$ act
```

ポートを確認してSSHを使う方法

```bash
$ limactl ls
NAME                        STATUS     SSH                VMTYPE    ARCH      CPUS    MEMORY    DISK      DIR
ubuntu-vm                   Running    127.0.0.1:50088    qemu      x86_64    1       1GiB      6GiB      ~/.lima/ubuntu-vm

$ ssh 127.0.0.1 -p 50088 uname -m
x86_64
```

とがあります。実態はどちらもSSHのようです。

なお `limactl shell` コマンドでVMに入った場合のworking directoryは、デフォルトでホストにおけるカレントディレクトリとなる[実装](https://github.com/lima-vm/lima/blob/4e1cfac182108ed8bb1fd1b8c7d2f79b3c359603/cmd/limactl/shell.go#L100)のようです。
つまり、もし `limactl shell` を実行したディレクトリが `/A/B/C` だとしたら、そのディレクトリがVM内にマウントされているかどうかによらず、 `limactl shell` を実行した際にそのVMでのシェルが `cd /A/B/C` された状態となります。

サンプルconfigでも

```yaml
mounts:
  - location: "~"
```

といった記述が目立つように、limaではVM内にホストと同じディレクトリ階層が見える形にすることを基本的に想定しているようですので、その郷に従ったほうが余計なトラブルは防げるかもしれません。従っていない場合、例えば `limactl shell` した際に `bash: line 1: cd: /invisible/directory: No such file or directory` と出ます（それ以外の実害は観測していませんが、他にも罠のもとになるかもなので避けるのが無難そう）。

一応 `--workdir` というオプションで指定することもできます。
```bash
$ pwd
/path/to/project/workdir

$ limactl shell --workdir /path/to/other/dir ubuntu-vm
(ubuntu-vm)$ pwd
/path/to/other/dir
```

本稿のサンプルの `ubuntu-vm.yml` では、さすがにホームをまるごとマウントする意味はないのでそれはせず、作業プロジェクトのワークツリーがそのままVM内で同じディレクトリツリーとして見える形でマウントすることを想定しています。


# パフォーマンス

エミュレーションによりx86のバイナリを実行しているためVM内のパフォーマンスはかなり制限されます。
軽く計測してみると以下のようになりました。

| タスク | Lima x86 VM | Lima+aarch64 native VM | 倍率 |
|:--|:--|:--|:--|
| 上記ubuntu-vmの作成（再起動1回込み） | 435秒 | 105秒 | 4.1x |
| UnixBench dhrystone (1CPU) | 6,549,534.7lps | 97,751,561.2lps | 14.9x |
| UnixBench whetstone (1CPU) | 764.8WMIPS | 8914.6WMIPS | 11.7x |
| UnixBench syscall (1CPU) | 269405.9lps | 1566354.8lps | 5.8x |
| UnixBench spawn (1CPU) | 1298.2lps | 9837.8lps | 7.6x |
| UnixBench shell1 (1CPU) | 1420.8lpm | 11661.5lpm | 8.2x |

計算要素の多いものは10~15倍程度、OS関連（IO待ちやシステムコール系）が絡む処理で4~8倍程度遅いという結果。例えば開発作業そのもののメイン環境として使うには厳しいものの、必要な場面でのCIの再現などの用途には実行待ち時間との比較などで考えると十分実用的です。
