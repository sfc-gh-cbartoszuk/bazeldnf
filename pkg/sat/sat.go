package sat

import (
	"fmt"

	"github.com/rmohr/bazel-dnf/pkg/api"
	"github.com/sirupsen/logrus"
)

type VarType string

const (
	VarTypePackage  = "Package"
	VarTypeResource = "Resource"
	VarTypeFile     = "File"
)

// VarContext contains all information to create a unique identifyable hash key which can be traced back to a package
// for every resource in a yum repo
type VarContext struct {
	Package  string
	Provides string
	Version  api.Version
}

type Var struct {
	satVarName int
	varType    VarType
	Context    VarContext
	Package    *api.Package
}

type Resolver struct {
	varsCount int
	// provides allows accessing variables which can resolve an unversioned requirement
	provides map[string][]*Var
	// pkgProvides allows accessing all variables which get pulled in if a specific package get's pulled in
	// this is useful to construct xor clauses
	pkgProvides map[VarContext][]*Var
	// vars contain as key an exact identifier for a provided resource and the actual SAT variable as value
	vars map[VarContext]*Var
}

func NewResolver() *Resolver {
	return &Resolver{
		varsCount:   0,
		provides:    map[string][]*Var{},
		vars:        map[VarContext]*Var{},
		pkgProvides: map[VarContext][]*Var{},
	}
}

func (r *Resolver) ticket() int {
	r.varsCount++
	return r.varsCount
}

func (r *Resolver) LoadInvolvedPackages(packages []*api.Package) error {
	for _, pkg := range packages {
		pkgVar, resourceVars := r.explodePackageToVars(pkg)
		r.pkgProvides[pkgVar.Context] = append(resourceVars, pkgVar)
		for _, v := range append(resourceVars, pkgVar) {
			r.provides[v.Context.Provides] = append(r.provides[v.Context.Provides], v)
			r.vars[v.Context] = v
		}
		logrus.Debug(pkgVar)
		logrus.Debug(resourceVars)
	}
	return nil
}

func (r *Resolver) ConstructRequirements(packages []*api.Package) error {

	return nil
}

func (r *Resolver) Resolve() error {
	return nil
}

func (r *Resolver) explodePackageToVars(pkg *api.Package) (pkgVar *Var, resourceVars []*Var) {
	for _, p := range pkg.Format.Provides.Entries {
		if p.Text == pkg.Name {
			pkgVar = &Var{
				satVarName: r.ticket(),
				varType:    VarTypePackage,
				Context: VarContext{
					Package:  pkg.Name,
					Provides: pkg.Name,
					Version:  pkg.Version,
				},
				Package: pkg,
			}
		} else {
			resVar := &Var{
				satVarName: r.ticket(),
				varType:    VarTypeResource,
				Context: VarContext{
					Package:  pkg.Name,
					Provides: p.Name,
					Version:  pkg.Version,
				},
				Package: pkg,
			}
			resourceVars = append(resourceVars, resVar)
		}
	}

	for _, f := range pkg.Format.Files {
		resVar := &Var{
			satVarName: r.ticket(),
			varType:    VarTypeFile,
			Context: VarContext{
				Package:  pkg.Name,
				Provides: f.Text,
				Version:  pkg.Version,
			},
			Package: pkg,
		}
		resourceVars = append(resourceVars, resVar)
	}
	return pkgVar, resourceVars
}

func (r *Resolver) explodePackageRequires(pkg *api.Package) {
	for _, req := range pkg.Format.Requires.Entries {
		r.explodeSingleRequires(req, r.provides[req.Name])
	}
}

func (r *Resolver) explodeSingleRequires(entry api.Entry, packages []*Var) (accepts []*Var, err error) {
	switch entry.Flags {
	case "EQ":
		for _, dep := range packages {
			if entry.Epoch == dep.Package.Version.Epoch &&
				entry.Ver == dep.Package.Version.Ver &&
				entry.Rel == dep.Package.Version.Rel {
				accepts = append(accepts, dep)
				break
			}
		}
	case "LE":
		for _, dep := range packages {
			if entry.Epoch == dep.Package.Version.Epoch &&
				entry.Ver == dep.Package.Version.Ver &&
				entry.Rel == dep.Package.Version.Rel {
				accepts = append(accepts, dep)
			}
		}
		return accepts, nil
	case "GE":
	case "":
	default:
		return nil, fmt.Errorf("can't interprate flags value %s", entry.Flags)
	}
	return nil, nil
}
