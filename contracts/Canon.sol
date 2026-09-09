// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  Canon — статья 2: ядро меняется только явным форком.
/// @notice Контракт не хранит текст конституции. Он хранит его хэш и делает
///         так, что тихо подменить ядро невозможно: не потому, что кто-то
///         запретил, а потому, что переменной для записи не существует.
///
///         Что здесь есть и чего нет:
///
///         НЕТ прокси и delegatecall. Это принципиально. Прокси — ровно тот
///         механизм, которым «неизменяемый» контракт меняют за ночь одной
///         транзакцией администратора. Адрес этого контракта и есть его код.
///
///         НЕТ владельца, способного тронуть ядро. Стюарды правят только
///         изменяемую часть и только через таймлок.
///
///         НЕТ голосования по ядру. Голосовать за то, чтобы ядро стало другим,
///         бессмысленно: результат такого голосования нечем исполнить.
///         Единственный путь — форк, и он открыт всем без разрешения.
///
///         ЕСТЬ реестр форков, который этот контракт не может отклонить.
///         Статья 12: ни одна версия не вправе объявить другую вне закона.
interface ICanon {
    function predecessor() external view returns (address);
    function coreHash()    external view returns (bytes32);
}

contract Canon {
    // ---------------------------------------------------------------
    // Ядро. Статьи 1–6.
    //
    // `immutable` в Solidity означает, что значение вшивается в байт-код
    // при деплое и живёт не в storage. К нему физически не ведёт ни один
    // SSTORE. Ни стюарды, ни автор контракта, ни компрометация ключей
    // не меняют эти четыре значения — их можно только перестать читать,
    // развернув другой контракт. Что и называется форком.
    // ---------------------------------------------------------------
    bytes32 public immutable coreHash;    // keccak256 канонических байтов ядра
    bytes32 public immutable coreDigest;  // sha2-256 тех же байтов, для IPFS CIDv1
    address public immutable predecessor; // 0x0 у первой версии
    uint64  public immutable bornAt;

    /// @notice Где лежит текст ядра. Записывается в конструкторе.
    ///         Строку нельзя объявить immutable, поэтому гарантия здесь другая
    ///         и она слабее: в контракте просто нет функции, которая её пишет.
    ///         Проверять текст следует по coreHash, а не по доверию к ссылке.
    string public coreURI;

    // ---------------------------------------------------------------
    // Изменяемая часть. Статьи 7 и дальше, приложения, регламенты.
    // ---------------------------------------------------------------
    bytes32 public bodyHash;
    string  public bodyURI;
    uint64  public bodyVersion;

    // ---------------------------------------------------------------
    // Стюарды. Правят изменяемую часть, к ядру доступа не имеют.
    // Смена подписантов не меняет статьи 1–6 — это свойство типа,
    // а не обещание в уставе.
    // ---------------------------------------------------------------
    address public stewards;
    uint64  public constant DELAY = 7 days;

    // ---------------------------------------------------------------
    // Переходные полномочия основателя и их автоматический конец.
    //
    // Пока не наступил срок, стюарды правят изменяемую часть. После —
    // полномочия переходят к `successor` и обратно не возвращаются.
    //
    // Все три величины immutable, и это здесь главное. Носитель
    // полномочий не может ни отодвинуть дату, ни поднять порог, ни
    // переназначить преемника в последний момент. Пункт о сроке,
    // который его носитель вправе продлить, сроком не является.
    //
    // Дата — основной триггер: её нельзя ни ускорить, ни отсрочить
    // никому. Число принявших — дополнительный и работает только на
    // ускорение; полагаться на него как на меру поддержки нельзя,
    // подписи дёшевы (см. PRECEDENTS.md).
    // ---------------------------------------------------------------
    uint64  public immutable sunsetDate;      // unix time, безусловный предел
    uint64  public immutable sunsetAdopters;  // порог принявших, 0 = выключен
    address public immutable successor;       // кому переходит, решено при деплое

    /// @dev Защёлка. `adopters` умеет убывать при выходе, и без неё
    ///      полномочия могли бы вернуться после того, как истекли.
    bool public sunsetLatched;

    struct Pending { bytes32 hash_; string uri; uint64 eta; }
    Pending public pending;

    // ---------------------------------------------------------------
    // Принятие. Подпись кошельком, а не лайк на сайте.
    // ---------------------------------------------------------------
    struct Adoption { uint64 at; bool active; }
    mapping(address => Adoption) public adoption;
    uint64 public adopters;

    // ---------------------------------------------------------------
    // Форки. Список только растёт, порядка старшинства в нём нет.
    // ---------------------------------------------------------------
    address[] public forks;
    mapping(address => bool) public noted;

    error NotSteward();
    error CoreMismatch(bytes32 expected, bytes32 given);
    error NotAFork();
    error AlreadyNoted();
    error NothingPending();
    error TooEarly(uint64 eta);
    error NotAdopted();
    error SunsetInThePast();

    event Adopted(address indexed who, bytes32 core);
    event Renounced(address indexed who);
    event BodyProposed(bytes32 indexed hash_, string uri, uint64 eta);
    event BodyAmended(uint64 indexed version, bytes32 indexed hash_, string uri);
    event StewardsChanged(address indexed from, address indexed to);
    event ForkNoted(address indexed canon, bytes32 core);
    event Sunset(uint64 at, uint64 adopters, address indexed successor);

    modifier onlyStewards() {
        if (msg.sender != effectiveStewards()) revert NotSteward();
        _;
    }

    /// @notice Истекли ли переходные полномочия. Читается кем угодно.
    function sunsetReached() public view returns (bool) {
        if (sunsetLatched) return true;
        if (block.timestamp >= sunsetDate) return true;
        return sunsetAdopters != 0 && adopters >= sunsetAdopters;
    }

    /// @notice Кто на самом деле правит изменяемой частью прямо сейчас.
    ///         До срока — стюарды, после — преемник, названный при деплое.
    function effectiveStewards() public view returns (address) {
        return sunsetReached() ? successor : stewards;
    }

    constructor(
        bytes32 _coreHash,
        bytes32 _coreDigest,
        string memory _coreURI,
        bytes32 _bodyHash,
        string memory _bodyURI,
        address _stewards,
        address _predecessor,
        uint64  _sunsetDate,
        uint64  _sunsetAdopters,
        address _successor
    ) {
        coreHash    = _coreHash;
        coreDigest  = _coreDigest;
        coreURI     = _coreURI;
        predecessor = _predecessor;
        bornAt      = uint64(block.timestamp);

        bodyHash    = _bodyHash;
        bodyURI     = _bodyURI;
        bodyVersion = 1;

        stewards    = _stewards;

        // Дата обязательна: без неё полномочия не кончаются никогда,
        // а порог по числу принявших накручиваем и потому не гарантия.
        if (_sunsetDate <= block.timestamp) revert SunsetInThePast();
        sunsetDate     = _sunsetDate;
        sunsetAdopters = _sunsetAdopters;
        successor      = _successor;
    }

    // ---------------------------------------------------------------
    // Проверка текста
    // ---------------------------------------------------------------

    /// @notice Совпадает ли текст, который у вас на руках, с принятым ядром.
    ///         Читается кем угодно и ничего не стоит.
    function verifyCore(bytes calldata text) external view returns (bool) {
        return keccak256(text) == coreHash;
    }

    function verifyBody(bytes calldata text) external view returns (bool) {
        return keccak256(text) == bodyHash;
    }

    // ---------------------------------------------------------------
    // Принятие и выход
    // ---------------------------------------------------------------

    /// @notice Принять протокол. Хэш ядра передаётся явно: подписывающий
    ///         обязан назвать, под какой именно текст он подписывается.
    ///         Это защищает от подсовывания форка под видом оригинала —
    ///         у форка другой coreHash, и вызов просто не пройдёт.
    function adopt(bytes32 core) external {
        if (core != coreHash) revert CoreMismatch(coreHash, core);
        if (!adoption[msg.sender].active) {
            adoption[msg.sender] = Adoption(uint64(block.timestamp), true);
            unchecked { adopters += 1; }
            emit Adopted(msg.sender, core);

            if (!sunsetLatched && sunsetAdopters != 0 && adopters >= sunsetAdopters) {
                sunsetLatched = true;
                emit Sunset(uint64(block.timestamp), adopters, successor);
            }
        }
    }

    /// @notice Выйти. Статья 3: право уйти неотъемлемо, поэтому здесь нет
    ///         ни условий, ни срока уведомления, ни чужой подписи.
    function renounce() external {
        if (!adoption[msg.sender].active) revert NotAdopted();
        adoption[msg.sender].active = false;
        unchecked { adopters -= 1; }
        emit Renounced(msg.sender);
    }

    // ---------------------------------------------------------------
    // Поправки к изменяемой части
    // ---------------------------------------------------------------

    /// @notice Предложить новую редакцию изменяемой части.
    ///         Публикуется сразу, вступает в силу не раньше чем через DELAY —
    ///         чтобы принявшие успели прочитать и при несогласии выйти
    ///         до того, как поправка начнёт действовать.
    function proposeBody(bytes32 hash_, string calldata uri) external onlyStewards {
        uint64 eta = uint64(block.timestamp) + DELAY;
        pending = Pending(hash_, uri, eta);
        emit BodyProposed(hash_, uri, eta);
    }

    /// @notice Ввести отлежавшуюся поправку. Вызвать может кто угодно:
    ///         после таймлока это механическое действие, держать его
    ///         за стюардами незачем.
    function amendBody() external {
        Pending memory p = pending;
        if (p.eta == 0) revert NothingPending();
        if (block.timestamp < p.eta) revert TooEarly(p.eta);

        bodyHash = p.hash_;
        bodyURI  = p.uri;
        unchecked { bodyVersion += 1; }
        delete pending;

        emit BodyAmended(bodyVersion, bodyHash, bodyURI);
    }

    function cancelBody() external onlyStewards {
        delete pending;
    }

    /// @notice Передать стюардство. Ядра не касается ни при каких условиях:
    ///         coreHash не имеет сеттера вовсе.
    ///
    ///         После истечения переходных полномочий вызвать это может уже
    ///         только преемник: модификатор смотрит на effectiveStewards().
    ///         Основатель не может ни назначить себе замену на будущее,
    ///         ни вернуть себе полномочия задним числом.
    function transferStewards(address to) external onlyStewards {
        emit StewardsChanged(stewards, to);
        stewards = to;
    }

    // ---------------------------------------------------------------
    // Форк
    // ---------------------------------------------------------------

    /// @notice Записать форк этого канона.
    ///
    ///         Кто угодно разворачивает новый Canon, указав этот адрес как
    ///         predecessor, и затем вызывает эту функцию. Контракт проверяет
    ///         только родство — и не может отказать. Ни стюарды, ни принявшие
    ///         не имеют права вето: статья 12.
    ///
    ///         Регистрировать после деплоя, а не из конструктора: пока
    ///         конструктор не вернулся, кода по адресу ещё нет и внешний
    ///         вызов к нему не проходит.
    ///
    ///         Принявшие сюда не переносятся. Список принявших живёт в своём
    ///         контракте, у форка он пустой. Это и есть «потеря прежней
    ///         легитимности» из статьи 2 — не приговор, а устройство: новую
    ///         версию нужно принимать заново, отдельной подписью.
    function noteFork(address canon) external {
        if (ICanon(canon).predecessor() != address(this)) revert NotAFork();
        if (noted[canon]) revert AlreadyNoted();
        noted[canon] = true;
        forks.push(canon);
        emit ForkNoted(canon, ICanon(canon).coreHash());
    }

    function forkCount() external view returns (uint256) {
        return forks.length;
    }
}
