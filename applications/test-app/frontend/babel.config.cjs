module.exports = function(api) {
  // Check environment first (before configuring cache)
  const isTest = api.env('test');
  
  // Configure Babel caching - cache forever since config doesn't change
  api.cache(true);
  
  return {
    presets: [
      [
        '@babel/preset-env',
        {
          targets: { node: 'current' },
          modules: isTest ? 'auto' : false, // Use ES modules for faster transforms in tests
          useBuiltIns: false, // Don't polyfill (not needed for tests)
        },
      ],
      ['@babel/preset-react', { runtime: 'automatic' }],
    ],
    plugins: [
      // Transform import.meta.env to a mock object for Jest
      function(pluginApi) {
        const t = pluginApi.types || require('@babel/core').types;
        return {
          visitor: {
            MemberExpression(path) {
              // Check if this is import.meta.env
              const { node } = path;
              if (
                node.object &&
                node.object.type === 'MetaProperty' &&
                node.object.meta &&
                node.object.meta.name === 'import' &&
                node.object.property &&
                node.object.property.name === 'meta' &&
                node.property &&
                node.property.name === 'env'
              ) {
                // Replace with a mock object
                path.replaceWith(t.objectExpression([
                  t.objectProperty(
                    t.identifier('env'),
                    t.objectExpression([
                      t.objectProperty(t.identifier('VITE_BACKEND_URL'), t.stringLiteral('http://localhost:8000')),
                      t.objectProperty(t.identifier('MODE'), t.stringLiteral('test')),
                      t.objectProperty(t.identifier('DEV'), t.booleanLiteral(false)),
                      t.objectProperty(t.identifier('PROD'), t.booleanLiteral(false)),
                      t.objectProperty(t.identifier('SSR'), t.booleanLiteral(false)),
                    ])
                  ),
                ]));
              }
            },
          },
        };
      },
    ],
  };
};

