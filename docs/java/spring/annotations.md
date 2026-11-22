# Annotations

## Spring Annotations

### `@PostConstruct`

`@PostConstruct` marks a method that Spring calls **once, right after a bean is created and its dependencies are injected**. It is the place for initialization logic that needs injected fields, which aren't available inside the constructor of a field-injected bean.

It comes from the Jakarta (formerly Java EE) common annotations, not from Spring itself, but Spring supports it out of the box.

#### Import

```java
// Spring Boot 3.x / Spring 6+ (Jakarta EE 9+)
import jakarta.annotation.PostConstruct;

// Spring Boot 2.x / Spring 5
import javax.annotation.PostConstruct;
```

This is a common source of compile errors when upgrading from Boot 2 to 3.

#### Example

```java
@Service
public class CacheService {

    @Autowired
    private ProductRepository productRepository;   // injected AFTER the constructor runs

    private Map<Long, Product> cache;

    public CacheService() {
        // productRepository is still null here
    }

    @PostConstruct
    public void init() {
        // Safe: all dependencies are injected
        cache = productRepository.findAll().stream()
                .collect(Collectors.toMap(Product::getId, p -> p));
        System.out.println("Cache loaded with " + cache.size() + " products");
    }
}
```

#### Bean lifecycle: where it fits

1. Spring instantiates the bean (constructor runs)
2. Dependencies are injected (`@Autowired`, setters)
3. `*Aware` callbacks run (e.g. `BeanNameAware`, `ApplicationContextAware`)
4. `BeanPostProcessor.postProcessBeforeInitialization`
5. **`@PostConstruct` method runs**
6. `InitializingBean.afterPropertiesSet()`
7. Custom `init-method` (`@Bean(initMethod = "...")`)
8. `BeanPostProcessor.postProcessAfterInitialization`
9. Bean is ready for use
10. On shutdown: **`@PreDestroy`**, then `DisposableBean.destroy()`, then custom `destroy-method`

#### Rules for the annotated method

- It must take **no parameters**
- Its return type should be `void` (the return value is ignored)
- It can have any visibility, but is normally `public` or `protected`
- It must not be `static`
- It should not throw checked exceptions. If it throws any exception, bean creation fails and the application context fails to start.
- Only **one** method per class should carry it
- It runs once per bean instance (for a prototype-scoped bean, once per created instance)

#### Typical uses

- Loading reference data or warming a cache at startup
- Validating configuration properties
- Opening connections or starting background threads
- Initializing derived fields from injected values

#### Alternatives and caveats

**Constructor injection often removes the need for it.** If you inject through the constructor, dependencies are already available in the constructor:

```java
@Service
public class CacheService {
    private final ProductRepository repo;

    public CacheService(ProductRepository repo) {
        this.repo = repo;
        // repo is usable here
    }
}
```

`@PostConstruct` is still useful when you want to keep initialization separate from construction.

**Don't do slow work in it.** It runs during context startup, so a long database call or remote request delays application start, and a failure prevents the app from starting at all.

**Transactions and proxies are not ready.** `@Transactional`, `@Async`, and `@Cacheable` work through proxies, and in `@PostConstruct` the proxy isn't fully set up yet, so annotated methods called from it may not behave as expected. Run work that needs the full context after startup instead.

**Better options for startup tasks that need the whole app:**

```java
// Runs after the application context is fully ready
@EventListener(ApplicationReadyEvent.class)
public void onReady() { ... }

// Or, for Spring Boot
@Component
public class StartupRunner implements ApplicationRunner {
    @Override
    public void run(ApplicationArguments args) { ... }
}
```

**Other approaches:**

- `InitializingBean.afterPropertiesSet()` achieves the same, but couples your code to Spring
- `@Bean(initMethod = "init")` keeps the class free of annotations, useful for third-party classes

### `@PreDestroy`

`@PreDestroy` runs just before the bean is removed (application shutdown), and is used to release resources such as closing connections or stopping threads:

```java
@PreDestroy
public void cleanup() {
    executor.shutdown();
}
```

## Spring Boot Annotations
